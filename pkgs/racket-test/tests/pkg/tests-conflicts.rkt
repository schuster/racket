#lang racket/base
(require rackunit
         racket/system
         racket/match
         racket/format
         (for-syntax racket/base
                     syntax/parse)
         racket/file
         racket/runtime-path
         racket/path
         racket/list
         "shelly.rkt"
         "util.rkt")

(this-test-is-run-by-the-main-test)

(pkg-tests
 (shelly-begin
  (initialize-catalogs)
  
  $ "raco pkg create --format plt test-pkgs/pkg-test1/"
  $ "raco pkg create --format plt test-pkgs/pkg-test1-not-conflict/"
  (shelly-install "only modules are considered for conflicts"
                  "test-pkgs/pkg-test1.plt"
                  $ "raco pkg install test-pkgs/pkg-test1-not-conflict.plt")

  (shelly-case
   "conflicts"
   (shelly-install "double install fails" "test-pkgs/pkg-test1.zip"
                   $ "raco pkg install test-pkgs/pkg-test1.zip" =exit> 1)

   (with-fake-root
    (shelly-case
     "conflicts with racket fail"
     $ "test -f test-pkgs/racket-conflict.tgz"
     $ "raco pkg install test-pkgs/racket-conflict.tgz" =exit> 1))

   (shelly-install "conflicts are caught" "test-pkgs/pkg-test1.zip"
                   $ "test -f test-pkgs/pkg-test1-conflict.zip"
                   $ "raco pkg install test-pkgs/pkg-test1-conflict.zip" =exit> 1)

   (shelly-install "conflicts are caught across sharing modes" "test-pkgs/pkg-test1.zip"
                   $ "test -f test-pkgs/pkg-test1-conflict.zip"
                   $ "raco pkg install -s test-pkgs/pkg-test1-conflict.zip" =exit> 1)

   (shelly-install "conflicts are caught for compiled files" "test-pkgs/pkg-test1.zip"
                   $ "test -f test-pkgs/pkg-test1b.zip"
                   $ "raco pkg install test-pkgs/pkg-test1b.zip" =exit> 1)

   (shelly-install* "conflicts are caught in single-collection" 
                    "test-pkgs/pkg-test1.zip test-pkgs/pkg-test3.zip" "pkg-test1 pkg-test3"
                    $ "test -f test-pkgs/pkg-test3-v2.zip"
                    $ "raco pkg install test-pkgs/pkg-test3-v2.zip" =exit> 1)
   (shelly-install* "conflicts are caught in single-collection against multi-collection"
                    "test-pkgs/pkg-test1.zip test-pkgs/pkg-test3-v2.zip" "pkg-test1 pkg-test3-v2"
                    $ "test -f test-pkgs/pkg-test3.zip"
                    $ "raco pkg install test-pkgs/pkg-test3.zip" =exit> 1)

   (define tmp-dir (path->directory-path (make-temporary-file "pkg~a" 'directory)))
   (shelly-wind
    $ (~a "cp -r test-pkgs/pkg-test1 " tmp-dir"pkg-test1-linking")
    $ (~a "raco pkg install --link " tmp-dir"pkg-test1-linking")
    $ "test -f test-pkgs/pkg-test1-conflict.zip"
    $ "raco pkg install test-pkgs/pkg-test1-conflict.zip" =exit> 1
    $ "raco pkg remove pkg-test1-linking"
    (finally
     (delete-directory/files tmp-dir)))

   (shelly-install "conflicts can be forced" "test-pkgs/pkg-test1.zip"
                   $ "racket -e '(require pkg-test1/conflict)'" =exit> 42
                   $ "raco pkg install --force test-pkgs/pkg-test1-conflict.zip" =exit> 0
                   $ "racket -e '(require pkg-test1/conflict)'" =exit> 42
                   $ "raco pkg remove pkg-test1-conflict")

   (shelly-install "conflicts can be forced" "test-pkgs/pkg-test1-conflict.zip"
                   $ "racket -e '(require pkg-test1/conflict)'" =exit> 43
                   $ "raco pkg install --force test-pkgs/pkg-test1.zip" =exit> 0
                   $ "racket -e '(require pkg-test1/conflict)'" =exit> 43
                   $ "raco pkg remove pkg-test1-conflict"))

  (with-fake-root
    (shelly-case
     "update succeeds when module is moved to dependency"
     (define tmp-dir (path->directory-path (make-temporary-file "pkg~a" 'directory)))
     
     (shelly-wind
      (define a-dir (build-path tmp-dir "a"))
      (make-directory a-dir)
      (set-file (build-path a-dir "info.rkt") "#lang info\n(define collection \"a\")\n")
      (set-file (build-path a-dir "apple.rkt") "#lang racket/base\n")

      (define b-dir (build-path tmp-dir "b"))
      (make-directory b-dir)
      (set-file (build-path b-dir "info.rkt") "#lang info\n(define collection \"a\")\n")
      (set-file (build-path b-dir "apple.rkt") "#lang racket/base\n")
      
      $ (~a "raco pkg install --copy " a-dir " " b-dir)
      =exit> 1 
      =stderr> #rx"packages conflict"
      
      $ (~a "raco pkg install --copy " a-dir)
      (set-file (build-path a-dir "info.rkt") 
                (~a "#lang info\n(define collection \"a\")\n"
                    "(define deps '((" (~s (path->string b-dir)) ")))\n"))
      $ (~a "raco pkg update --auto --copy " a-dir)
      =exit> 1 
      =stderr> #rx"packages conflict"
      
      (delete-file (build-path a-dir "apple.rkt"))
      $ (~a "raco pkg update --auto --copy " a-dir)
      
      (finally
       (delete-directory/files tmp-dir)))))

  (shelly-case
   "conflict extra installs"
   (for ([c '("test-pkgs/pkg-add-a"
             "test-pkgs/pkg-add-x"
             "test-pkgs/pkg-add-1")])
    (with-fake-root
     (shelly-begin
      $ (~a "raco pkg install --copy --strict-doc-conflicts test-pkgs/pkg-add-base " c) =exit> 1
      $ (~a "raco pkg install --copy --strict-doc-conflicts " c "test-pkgs/pkg-add-base") =exit> 1))))
  (shelly-case
   "doc conflict allowed in non-strict mode"
   (for ([c '("test-pkgs/pkg-add-a")])
    (with-fake-root
     (shelly-begin
      $ (~a "raco pkg install --copy test-pkgs/pkg-add-base " c) =exit> 0))))
  (putenv "PLT_PKG_NOSETUP" "")
  (with-fake-root
   (shelly-case
    "conflict extra installs with already installed"
    $ (~a "raco pkg install --copy test-pkgs/pkg-add-base") =exit> 0
    (for ([c '("test-pkgs/pkg-add-a"
               "test-pkgs/pkg-add-x"
               "test-pkgs/pkg-add-1")])
      (shelly-begin
       $ (~a "raco pkg install --copy --strict-doc-conflicts " c) =exit> 1)))
   (for ([c '("test-pkgs/pkg-add-a")])
    (with-fake-root
     (shelly-begin
      $ (~a "raco pkg install --copy --no-setup " c) =exit> 0))))
  (putenv "PLT_PKG_NOSETUP" "1")
  (with-fake-root
   (shelly-case
    "no conflict for non-matching platform"
    $ "raco pkg install --copy --strict-doc-conflicts test-pkgs/pkg-add-base test-pkgs/pkg-add-none"))
  (shelly-case
   "no doc conflict for an update"
   (for ([c '("test-pkgs/pkg-add-base"
              "test-pkgs/pkg-add-a"
              "test-pkgs/pkg-add-x"
              "test-pkgs/pkg-add-1")])
    (with-fake-root
     (shelly-begin
      $ "raco pkg install --copy test-pkgs/pkg-add-base"
      $ "raco setup -D --pkgs pkg-add-base"
      $ (~a "raco pkg update --copy --name pkg-add-base " c) =exit> 0))))

  (shelly-case
   "compile-omit-paths is used by `pkg-directory->additional-installs`:"
   $ (~a "racket -e '(require pkg/lib)' -e '"
         (~s '(pkg-directory->additional-installs
               (path-only (collection-file-path "test.rkt" "tests/pkg"))
               "racket-test"))
         "'")
   =stdout> "'()\n")))

(in-package "ACL2")

;  file-system-2.lisp                                  Mihir Mehta

; Here we define the rudiments of a file system with length tracking.  We first
; start with a file-system recognizer, and then we define various file-system
; operations.

; The important functions are l2-to-l1-fs, l2-stat, l2-rdchs and
; l2-wrchs. Each of them is preceded by an explanatory comment. Equivalence
; theorems are stated and proved between each of these and the corresponding
; function in file-system-1.lisp. Moreover, the theorems l2-read-after-write-1
; and l2-read-after-write-2 prove two important properties of l2-rdchs and
; l2-wrchs anew, although they were proved in file-system-1 for the filesystem
; described therein.

(include-book "misc/assert" :dir :system)
(include-book "file-system-1")

; This function defines a valid filesystem. It's an alist where all the cars
; are symbols and all the cdrs are either further filesystems or files,
; separated into text (a string) and metadata (currently, only file length).
(defun l2-fs-p (fs)
  (declare (xargs :guard t))
  (if (atom fs)
      (null fs)
    (and (let ((directory-or-file-entry (car fs)))
           (if (atom directory-or-file-entry)
               nil
             (let ((name (car directory-or-file-entry))
                   (entry (cdr directory-or-file-entry)))
               (and (symbolp name)
                    (or (and (consp entry) (stringp (car entry)) (natp (cdr entry)))
                        (l2-fs-p entry))))))
         (l2-fs-p (cdr fs)))))

;; This example - which evaluates to t - remains as a counterexample to an
;; erstwhile bug.
(defconst *test01* (l2-fs-p '((a  "Mihir" . 5) (b "Warren" . 6) (c))))

;; This function transforms an instance of l2 into an equivalent instance of l1.
(defun l2-to-l1-fs (fs)
  (declare (xargs :guard (l2-fs-p fs)))
  (if (atom fs)
      fs
    (cons (let* ((directory-or-file-entry (car fs))
                 (name (car directory-or-file-entry))
                 (entry (cdr directory-or-file-entry)))
            (cons name
                (if (and (consp entry) (stringp (car entry)))
                    (car entry)
                  (l2-to-l1-fs entry))))
          (l2-to-l1-fs (cdr fs)))))

;; This theorem shows the type-correctness of l2-to-l1-fs.
(defthm l2-to-l1-fs-correctness-1
  (implies (l2-fs-p fs)
           (l1-fs-p (l2-to-l1-fs fs))))

(defthm alistp-l2-fs-p
  (implies (l2-fs-p fs)
           (alistp fs)))

(defthm l2-fs-p-assoc
  (implies (and (l2-fs-p fs)
                (consp (assoc-equal name fs))
                (consp (cddr (assoc-equal name fs))))
           (l2-fs-p (cdr (assoc-equal name fs)))))

(assert!
 (l2-fs-p '((a "Mihir" . 5) (b "Warren" . 6) (c (a "Mehta" . 5) (b "Hunt" . 4)))))

;; This function allows a file or directory to be found in a filesystem given a path.
(defun l2-stat (hns fs)
  (declare (xargs :guard (and (symbol-listp hns)
                              (l2-fs-p fs))))
  (if (atom hns)
      fs
    (if (atom fs)
        nil
      (let ((sd (assoc (car hns) fs)))
        (if (atom sd)
            nil
          (let ((contents (cdr sd)))
            (if (stringp (car contents))
                (and (null (cdr hns))
                     (car contents))
              (l2-stat (cdr hns) contents))))))))

(defthm l2-stat-correctness-1-lemma-1
  (implies (and (l2-fs-p fs))
           (iff (consp (assoc-equal name (l2-to-l1-fs fs)))
                (consp (assoc-equal name fs)))))

(defthm l2-stat-correctness-1-lemma-2
  (implies (and (l2-fs-p fs)
                (consp (assoc-equal name fs))
                (consp (cdr (assoc-equal name fs)))
                (stringp (car (cdr (assoc-equal name fs)))))
           (equal (cdr (assoc-equal name (l2-to-l1-fs fs)))
                  (car (cdr (assoc-equal name fs))))))

(defthm l2-stat-correctness-1-lemma-3
  (implies (and (l2-fs-p fs)
                (consp (assoc-equal name fs))
                (not (and (consp (cdr (assoc-equal name fs)))
                          (stringp (car (cdr (assoc-equal name fs)))))))
           (equal (cdr (assoc-equal name (l2-to-l1-fs fs)))
                  (l2-to-l1-fs (cdr (assoc-equal name fs))))))

(defthm l2-stat-correctness-1-lemma-4
  (implies (and (l2-fs-p fs) (stringp (cadr (assoc-equal name fs))))
           (equal (cdr (assoc-equal name (l2-to-l1-fs fs)))
                  (cadr (assoc-equal name fs))
                  )))

(defthm l2-stat-correctness-1-lemma-5
  (implies (and (consp (assoc-equal name fs))
                (not (stringp (cadr (assoc-equal name fs))))
                (l2-fs-p fs))
           (l2-fs-p (cdr (assoc-equal name fs)))))

;; This is the first of two theorems showing the equivalence of the l2 and l1
;; versions of stat.
(defthm l2-stat-correctness-1
  (implies (and (symbol-listp hns)
                (l2-fs-p fs)
                (stringp (l2-stat hns fs)))
           (equal (l1-stat hns (l2-to-l1-fs fs))
                  (l2-stat hns fs))))

(defthm l2-stat-correctness-2-lemma-1
  (implies (and (l2-fs-p fs) (consp (assoc-equal name fs)))
           (implies (not (stringp (cadr (assoc-equal name fs))))
                    (not (stringp (cdr (assoc-equal name (l2-to-l1-fs fs))))))))

(defthm l2-stat-correctness-2-lemma-2
  (implies (not (stringp fs))
           (not (stringp (l2-to-l1-fs fs)))))

;; This is the second of two theorems showing the equivalence of the l2 and l1
;; versions of stat.
(defthm l2-stat-correctness-2
  (implies (and (symbol-listp hns)
                (l2-fs-p fs)
                (l2-fs-p (l2-stat hns fs)))
           (equal (l1-stat hns (l2-to-l1-fs fs))
                  (l2-to-l1-fs (l2-stat hns fs))))
  )

;; This is simply a useful property of stat.
(defthm l2-stat-of-stat
  (implies (and (symbol-listp inside)
                (symbol-listp outside)
                (l2-stat outside fs)
                (l2-fs-p fs))
           (equal (l2-stat inside (l2-stat outside fs))
                  (l2-stat (append outside inside) fs)))
  :hints
  (("Goal"
    :induct (l2-stat outside fs))))

;; This function finds a text file given its path and reads a segment of
;; that text file.
(defun l2-rdchs (hns fs start n)
  (declare (xargs :guard (and (symbol-listp hns)
                              (l2-fs-p fs)
                              (natp start)
                              (natp n))))
  (let ((file (l2-stat hns fs)))
    (if (not (stringp file))
        nil
      (let ((file-length (length file))
            (end (+ start n)))
        (if (< file-length end)
            nil
          (subseq file start (+ start n)))))))

(defthm l2-rdchs-correctness-1-lemma-1
  (implies (and (l2-fs-p fs)
                (symbol-listp hns)
                (not (stringp (l2-stat hns fs))))
           (not (stringp (l1-stat hns (l2-to-l1-fs fs))))))

(defthm l2-rdchs-correctness-1-lemma-2
  (implies (l2-fs-p fs)
           (not (stringp (l2-to-l1-fs fs)))))

;; This theorem proves the equivalence of the l2 and l1 versions of stat.
(defthm l2-rdchs-correctness-1
  (implies (and (symbol-listp hns)
                (l2-fs-p fs)
                (natp start)
                (natp n))
           (equal (l1-rdchs hns (l2-to-l1-fs fs) start n)
                  (l2-rdchs hns fs start n))))

; This function deletes a file or directory given its path.
(defun l2-unlink (hns fs)
  (declare (xargs :guard (and (symbol-listp hns)
                              (l2-fs-p fs))))
  (if (atom hns)
      fs ;;error case, basically
    (if (atom (cdr hns))
        (delete-assoc (car hns) fs)
      (if (atom fs)
          nil
        (let ((sd (assoc (car hns) fs)))
          (if (atom sd)
              fs
            (let ((contents (cdr sd)))
              (if (stringp (car contents)) 
                  fs ;; we still have names but we're at a regular file - error
                (cons (cons (car sd)
                            (l2-unlink (cdr hns) contents))
                      (delete-assoc (car hns) fs))))))))
    ))

;; putting these lemmas on the back burner because we would need to add uniquep
;; to our l2-fs-p definition to make this work
;; (defthm l2-unlink-works-lemma-1 (not (assoc-equal key (delete-assoc-equal key alist))))

;; (defthm l2-unlink-works (implies (l2-fs-p fs) (not (l2-stat hns (l2-unlink hns fs)))))

(defthm l2-wrchs-guard-lemma-1
  (implies (and (stringp str))
           (character-listp (nthcdr n (coerce str 'list)))))

; This function writes a specified text string to a specified position to a
; text file at a specified path.
(defun l2-wrchs (hns fs start text)
  (declare (xargs :guard-debug t
                  :guard (and (symbol-listp hns)
                              (l2-fs-p fs)
                              (natp start)
                              (stringp text))
                  :guard-hints
                  (("Subgoal 1.4" :use (:instance character-listp-coerce (str ()))) )))
  (if (atom hns)
      fs ;; error - showed up at fs with no name  - so leave fs unchanged
    (if (atom fs)
        nil ;; error, so leave fs unchanged
      (let ((sd (assoc (car hns) fs)))
        (if (atom sd)
            fs ;; file-not-found error, so leave fs unchanged
          (let ((contents (cdr sd)))
            (cons (cons (car sd)
                        (if (and (consp (cdr sd)) (stringp (cadr sd)))
                            (let ((file (cdr sd)))
                              (if (cdr hns)
                                  file ;; error, so leave fs unchanged
                                (let* ((oldtext (coerce (car file) 'list))
                                       (newtext
                                        (insert-text oldtext start text))
                                       (newlength (len newtext)))
                                  (cons
                                   (coerce newtext 'string)
                                   newlength))))
                          (l2-wrchs (cdr hns) contents start text)))
                  (delete-assoc (car hns) fs))
            ))))))

(defthm l2-wrchs-returns-fs-lemma-1
  (implies (and (consp (assoc-equal s fs))
                (l2-fs-p fs))
           (symbolp (car (assoc-equal s fs)))))

(defthm l2-wrchs-returns-fs-lemma-2
  (implies (l2-fs-p fs)
           (l2-fs-p (delete-assoc-equal s fs))))

(defthm l2-wrchs-returns-fs-lemma-3
  (implies (and (consp fs) (l2-fs-p fs)
                (consp (assoc-equal s fs))
                (not (stringp (cadr (assoc-equal s fs)))))
           (l2-fs-p (cdr (assoc-equal s fs)))))

(defthm l2-wrchs-returns-fs-lemma-4
  (implies (and (consp fs)
                (consp (assoc-equal name fs))
                (l2-fs-p fs)
                (consp (cdr (assoc-equal name fs)))
                (stringp (cadr (assoc-equal name fs)))
                )
           (natp (cddr (assoc-equal name fs)))))

(defthm l2-wrchs-returns-fs-lemma-5
  (implies (and (l2-fs-p fs)
                (consp (assoc-equal name fs)))
           (symbolp name)))

;; This theorem shows that the property l2-fs-p is preserved by wrchs.
(defthm l2-wrchs-returns-fs
  (implies (l2-fs-p fs)
           (l2-fs-p (l2-wrchs hns fs start text))))

;; This theorem shows that the property l2-fs-p is preserved by unlink.
(defthm l2-unlink-returns-fs
  (implies (and (l2-fs-p fs))
           (l2-fs-p (l2-unlink hns fs))))

(defthm l2-wrchs-correctness-1-lemma-1
  (implies (l2-fs-p fs)
           (equal (delete-assoc-equal name (l2-to-l1-fs fs))
                  (l2-to-l1-fs (delete-assoc-equal name fs)))))

(defthm l2-wrchs-correctness-1-lemma-2
  (implies (and (consp fs)
                (l2-fs-p fs))
           (consp (l2-to-l1-fs fs))))

;; This theorem shows the equivalence of the l2 and l1 versions of wrchs.
(defthm l2-wrchs-correctness-1
  (implies (and (l2-fs-p fs)
                (stringp text)
                (natp start)
                (symbol-listp (cdr hns)))
           (equal (l1-wrchs hns (l2-to-l1-fs fs) start text)
                  (l2-to-l1-fs (l2-wrchs hns fs start text)))))

(defthm l2-read-after-write-1-lemma-1
  (implies (consp (assoc-equal name alist))
           (equal (car (assoc-equal name alist)) name)))

(defthm l2-read-after-write-1-lemma-2
  (implies (and (l2-fs-p fs) (stringp text) (stringp (l2-stat hns fs)))
           (stringp (l2-stat hns (l2-wrchs hns fs start text)))))

(defthm l2-read-after-write-1-lemma-3
  (implies (l2-rdchs hns fs start n)
           (stringp (l2-stat hns fs))))

(defthm l2-read-after-write-1-lemma-4
  (implies (and (l2-fs-p fs)
                (stringp text)
                (symbol-listp hns)
                (natp start)
                (stringp (l2-stat hns fs)))
           (<= (+ start (len (coerce text 'list)))
               (len (coerce (l2-stat hns (l2-wrchs hns fs start text))
                            'list)))))

;; This is a new proof of the first read-after-write property, which
;; does not rely upon the l1 proof of the same property.
(defthm l2-read-after-write-1
  (implies (and (l2-fs-p fs)
                (stringp text)
                (symbol-listp hns)
                (natp start)
                (equal n (length text))
                (stringp (l2-stat hns fs)))
           (equal (l2-rdchs hns (l2-wrchs hns fs start text) start n) text)))

;; The following comment details the induction scheme for the proof of
;; l2-read-after-write-2.
;; we want to prove
;; (implies (and (l2-fs-p fs)
;;               (stringp text2)
;;               (symbol-listp hns1)
;;               (symbol-listp hns2)
;;               (not (equal hns1 hns2))
;;               (natp start2)
;;               (stringp (l2-stat hns1 fs)))
;;          (equal (l2-stat hns1 (l2-wrchs hns2 fs start2 text2))
;;                 (l2-stat hns1 fs)))
;; now, let's semi-formally write the cases we want.
;; case 1: (atom hns1) - this will violate the hypothesis
;; (stringp (l2-stat hns1 fs))
;; case 2: (and (consp hns1) (atom fs)) - this will yield nil in both cases
;; case 3: (and (consp hns1) (consp fs) (atom (assoc (car hns1) fs))) - this
;; will yield nil in both cases (might need a lemma)
;; case 4: (and (consp hns1) (consp fs) (consp (assoc (car hns1) fs))
;;              (atom hns2)) - in this case
;; (l2-wrchs hns2 fs start2 text2) will be the same as fs
;; case 5: (and (consp hns1) (consp fs) (consp (assoc (car hns1) fs))
;;              (consp hns2) (not (equal (car hns1) (car hns2)))) - in this
;; case, (assoc (car hns1) (l2-wrchs hns2 fs start2 text2)) =
;; (assoc (car hns1) (delete-assoc (car hns2) fs)) =
;; (assoc (car hns1) fs) and from here on the terms will be equal
;; case 6: (and (consp hns1) (consp fs) (consp (assoc (car hns1) fs))
;;              (consp hns2) (equal (car hns1) (car hns2)) (atom (cdr hns1))) -
;; in this case (consp (cdr hns2)) is implicit because of
;; (not (equal hns1 hns2)) and (stringp (l2-stat hns1 fs)) implies that
;; (l2-wrchs hns2 fs start2 text2) = fs
;; case 7: (and (consp hns1) (consp fs) (consp (assoc (car hns1) fs))
;;              (consp hns2) (equal (car hns1) (car hns2)) (consp (cdr hns1))) -
;; (l2-stat hns1 (l2-wrchs hns2 fs start2 text2)) =
;; (l2-stat hns1 (cons (cons (car hns1)
;;                        (l2-wrchs (cdr hns2) (cdr (assoc (car hns1) fs)) start2 text2))
;;                  (delete-assoc (car hns1) fs)) =
;; (l2-stat (cdr hns1) (l2-wrchs (cdr hns2) (cdr (assoc (car hns1) fs)) start2 text2)) =
;; (l2-stat (cdr hns1) (cdr (assoc (car hns1) fs))) = (induction hypothesis)
;; (l2-stat hns1 fs)

(defthm l2-read-after-write-2-lemma-1
  (implies (l2-fs-p fs)
           (not (stringp (cdr (assoc-equal name fs))))))

(defthm l2-read-after-write-2-lemma-2
  (implies (and (consp hns1)
                (consp fs)
                (consp (assoc-equal (car hns1) fs))
                (l2-fs-p fs)
                (symbolp (car hns1))
                (not (cdr hns1))
                (stringp (l2-stat hns1 fs)))
           (equal (l2-stat hns1 fs) (cadr (assoc (car hns1) fs)))))

(encapsulate
  ()
  (local (defun induction-scheme (hns1 hns2 fs)
           (if (atom hns1)
               fs
             (if (atom fs)
                 nil
               (let ((sd (assoc (car hns2) fs)))
                 (if (atom sd)
                     fs
                   (if (atom hns2)
                       fs
                     (if (not (equal (car hns1) (car hns2)))
                         fs
                       (let ((contents (cdr sd)))
                         (if (atom (cdr hns1))
                             (cons (cons (car sd)
                                         contents)
                                   (delete-assoc (car hns2) fs))
                           (cons (cons (car sd)
                                       (induction-scheme (cdr hns1) (cdr hns2) contents))
                                 (delete-assoc (car hns2) fs)))
                         ))))
                 )))))

  (defthm l2-read-after-write-2-lemma-3
    (implies (and (l2-fs-p fs)
                  (stringp text2)
                  (symbol-listp hns1)
                  (symbol-listp hns2)
                  (not (equal hns1 hns2))
                  (natp start2)
                  (stringp (l2-stat hns1 fs)))
             (equal (l2-stat hns1 (l2-wrchs hns2 fs start2 text2)) (l2-stat hns1 fs)))
    :hints (("Goal"  :induct (induction-scheme hns1 hns2 fs))
            ("Subgoal *1/7.1''" :in-theory (disable alistp-l2-fs-p)
             :use (:instance alistp-l2-fs-p (fs (l2-wrchs (cdr hns2)
                                                    (cdr (assoc-equal (car hns1) fs))
                                                    start2 text2))))))

  )

;; This is a new proof of the second read-after-write property, which does not
;; rely on the equivalent proof in l1.
(defthm l2-read-after-write-2
  (implies (and (l2-fs-p fs)
                (stringp text2)
                (symbol-listp hns1)
                (symbol-listp hns2)
                (not (equal hns1 hns2))
                (natp start1)
                (natp start2)
                (natp n1)
                (stringp (l2-stat hns1 fs)))
           (equal (l2-rdchs hns1 (l2-wrchs hns2 fs start2 text2) start1 n1)
                  (l2-rdchs hns1 fs start1 n1))))

;; This function checks that the file lengths associated with text files are
;; accurate.
(defun l2-fsck (fs)
  (declare (xargs :guard (l2-fs-p fs)))
  (or (atom fs)
    (and (let ((directory-or-file-entry (car fs)))
           (let ((entry (cdr directory-or-file-entry)))
             (if (and (consp entry) (stringp (car entry)))
                 (equal (length (car entry)) (cdr entry))
               (l2-fsck entry))))
         (l2-fsck (cdr fs)))))

(defthm l2-fsck-after-l2-wrchs-lemma-1
  (implies (and (l2-fs-p fs) (l2-fsck fs))
           (l2-fsck (delete-assoc-equal name fs))))

(defthm l2-fsck-after-l2-wrchs-lemma-2
  (implies (and (l2-fs-p fs) (l2-fsck fs))
           (l2-fsck (cdr (assoc-equal (car hns) fs)))))

(defthm l2-fsck-after-l2-wrchs-lemma-3
  (implies (and (l2-fs-p fs) (consp fs)) (not (stringp (car fs)))))

(defthm l2-fsck-after-l2-wrchs-lemma-4
  (implies (and (consp fs)
                (consp (assoc-equal name fs))
                (l2-fs-p fs)
                (stringp text)
                (l2-fsck fs)
                (consp (cdr (assoc-equal name fs)))
                (stringp (cadr (assoc-equal name fs))))
           (equal (len (coerce (cadr (assoc-equal name fs))
                               'list))
                  (cddr (assoc-equal name fs))))
)

(encapsulate ()
  (local (include-book "std/strings/coerce" :dir :system))

  (defthm l2-fsck-after-l2-wrchs-lemma-5
    (implies (character-listp cl)
             (equal (coerce (coerce cl 'string) 'list)
                    cl)))

  )

;; This theorem shows that l2-fsck is preserved by l2-wrchs
(defthm l2-fsck-after-l2-wrchs
  (implies (and (l2-fs-p fs) (natp start) (stringp text) (l2-fsck fs))
           (l2-fsck (l2-wrchs hns fs start text))))

;; This theorem shows that l2-fsck is preserved by l2-unlink
(defthm l2-fsck-after-l2-unlink
  (implies (and (l2-fs-p fs) (l2-fsck fs))
           (l2-fsck (l2-unlink hns fs))))

; This function finds the length of the text file at a specified path
(defun l2-wc-len (hns fs)
  (declare (xargs :guard (and (symbol-listp hns)
                              (l2-fs-p fs))))
  (let ((file (l2-stat hns fs)))
    (if (not (stringp file))
        nil
      (length file))))

; Prove (list-of-chars-to-string (string-to-chars str))
;       (string-to-chars (list-of-chars-to-string char-list))
; and then, you will be positioned to use either form.
#||From :doc STR::STD/STRINGS/COERCE
  Theorem: <coerce-inverse-1-better>

    (defthm coerce-inverse-1-better
            (equal (coerce (coerce x 'string) 'list)
                   (if (stringp x)
                       nil (make-character-list x))))

  Theorem: <coerce-inverse-2-better>

    (defthm coerce-inverse-2-better
            (equal (coerce (coerce x 'list) 'string)
                   (if (stringp x) x "")))
That takes care of that
||#
; Correspond (or not) with Linux system calls -- the low-level stuff...

; Add file -- or, if you will, create a file with some initial contents

; and so on...

;; (assign fs '((a "Mihir" . 5) (b "Warren" . 6) (c (a "Mehta" . 5) (b "Hunt" . 4))))

;; (assign h1 '(a))
;; (assign h2 '(a b))
;; (assign h3 '(c b))
;; (assign h4 '(c))

;; (l2-stat (@ h1) (@ fs))
;; (l2-stat (@ h2) (@ fs))
;; (l2-stat (@ h3) (@ fs))
;; (l2-stat (@ h4) (@ fs))

;; (l2-wc-len (@ h1) (@ fs))
;; (l2-wc-len (@ h2) (@ fs))
;; (l2-wc-len (@ h3) (@ fs))
;; (l2-wc-len (@ h4) (@ fs))

;; (l2-wrchs (@ h1) (@ fs) 1 "athur")
;; (l2-wrchs (@ h3) (@ fs) 1 "inojosa")
;; (l2-wrchs (@ h3) (@ fs) 5 "Alvarez")
;; (l2-wrchs (@ h2) (@ fs) 1 "athur") ;; buggy example

;; (l2-unlink (@ h1) (@ fs))
;; (l2-unlink (@ h2) (@ fs))
;; (l2-unlink (@ h3) (@ fs))
;; (l2-unlink (@ h4) (@ fs))

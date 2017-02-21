(in-package "ACL2")

;  file-system-1.lisp                                  Mihir Mehta

; Here we define the rudiments of a file system.  We first start with
; a file-system recognizer, and then we define various file-system
; operations.

(include-book "misc/assert" :dir :system)
(include-book "file-system-lemmas")

(defun l1-fs-p (fs)
  (declare (xargs :guard t))
  (if (atom fs)
      (null fs)
    (and (let ((directory-or-file-entry (car fs)))
           (if (atom directory-or-file-entry)
               nil
             (let ((name (car directory-or-file-entry))
                   (entry (cdr directory-or-file-entry)))
               (and (symbolp name)
                    (or (stringp entry) (l1-fs-p entry))))))
         (l1-fs-p (cdr fs)))))
;; this example - which evaluates to t - remains as a counterexample to an
;; erstwhile bug.
(defconst *test01* (l1-fs-p '((a . "Mihir") (b . "Warren") (c))))

(defthm alistp-l1-fs-p
  (implies (l1-fs-p fs)
           (alistp fs)))

(defthm l1-fs-p-assoc
  (implies (and (l1-fs-p fs)
                (consp (assoc-equal name fs))
                (consp (cdr (assoc-equal name fs))))
           (l1-fs-p (cdr (assoc-equal name fs)))))

(assert!
 (l1-fs-p '((a . "Mihir") (b . "Warren") (c (a . "Mehta") (b . "Hunt")))))

(defun l1-stat (hns fs)
  (declare (xargs :guard (and (symbol-listp hns)
                              (l1-fs-p fs))))
  (if (atom hns)
      fs
    (if (atom fs)
        nil
      (let ((sd (assoc (car hns) fs)))
        (if (atom sd)
            nil
          (let ((contents (cdr sd)))
            (if (stringp contents)
                (and (null (cdr hns))
                     contents)
              (l1-stat (cdr hns) contents))))))))

(defthm l1-stat-of-l1-stat-lemma-1
  (implies (and (L1-FS-P FS)
                (CONSP (ASSOC-EQUAL name FS))
                (NOT (STRINGP (CDR (ASSOC-EQUAL name FS)))))
           (L1-FS-P (CDR (ASSOC-EQUAL name FS)))))

(defthm l1-stat-of-l1-stat
  (implies (and (symbol-listp inside)
                (symbol-listp outside)
                (l1-stat outside fs)
                (l1-fs-p fs))
           (equal (l1-stat inside (l1-stat outside fs))
                  (l1-stat (append outside inside) fs)))
  :hints
  (("Goal"
    :induct (l1-stat outside fs))))

(defun l1-rdchs (hns fs start n)
  (declare (xargs :guard (and (symbol-listp hns)
                              (l1-fs-p fs)
                              (natp start)
                              (natp n))))
  (let ((file (l1-stat hns fs)))
    (if (not (stringp file))
        nil
      (let ((file-length (length file))
            (end (+ start n)))
        (if (< file-length end)
            nil
          (subseq file start (+ start n)))))))

; More for Mihir to do...

; Delete file
(defun l1-unlink (hns fs)
  (declare (xargs :guard (and (symbol-listp hns)
                              (l1-fs-p fs))))
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
              (if (atom contents)
                  (and (null (cdr hns))
                       contents)
                (cons (cons (car sd) (l1-unlink (cdr hns) contents)) (delete-assoc (car hns) fs))))))))
    ))

(defund insert-text (oldtext start text)
  (declare (xargs :guard (and (character-listp oldtext)
                              (natp start)
                              (stringp text))))
  (let* (
         (end (+ start (length text)))
         (newtext (append (make-character-list (take start oldtext))
                          (coerce text 'list)
                          (nthcdr end oldtext))))
    newtext))

(defthm insert-text-correctness-1
  (implies (and (character-listp oldtext)
                (natp start)
                (stringp text))
           (character-listp (insert-text oldtext start text)))
  :hints (("Goal" :in-theory (enable insert-text)) ))

(defthm insert-text-correctness-2
  (implies (and (character-listp oldtext)
                (natp start)
                (stringp text))
           (equal (first-n-ac (+ start (- start)
                                 (len (coerce text 'list)))
                              (nthcdr start
                                      (insert-text (coerce (cdr (assoc-equal (car hns) fs))
                                                           'list)
                                                   start text))
                              nil)
                  (coerce text 'list)))
  :hints (("Goal" :in-theory (enable insert-text)) ))

(defthm insert-text-correctness-3
  (implies (and (character-listp oldtext)
                (stringp text)
                (natp start))
           (<= (+ start (len (coerce text 'list)))
               (len (insert-text oldtext start text))))
  :hints (("Goal" :in-theory (enable insert-text)) )
  :rule-classes :linear)

; The problem with this definition of l1-wrchs is that it deletes a directory if
; it's found where a text file is expected
(defun l1-wrchs (hns fs start text)
  (declare (xargs :guard (and (symbol-listp hns)
                              (or (stringp fs) (l1-fs-p fs))
                              (natp start)
                              (stringp text))))
  (if (atom hns)
      (let ((file fs))
        (if (not (stringp file))
            file ;; error, so leave fs unchanged
          (coerce
           (insert-text (coerce file 'list) start text)
           'string)))
    (if (atom fs)
        fs ;; error, so leave fs unchanged
      (let ((sd (assoc (car hns) fs)))
        (if (atom sd)
            fs ;; error, so leave fs unchanged
          (let ((contents (cdr sd)))
            (cons (cons (car sd) (l1-wrchs (cdr hns) contents start text))
                  (delete-assoc (car hns) fs))
            ))))))

(defthm l1-wrchs-returns-fs-lemma-1
  (implies (and (consp (assoc-equal s fs))
                (l1-fs-p fs))
           (symbolp (car (assoc-equal s fs)))))

(defthm l1-wrchs-returns-fs-lemma-2
  (implies (l1-fs-p fs)
           (l1-fs-p (delete-assoc-equal s fs))))

(defthm l1-wrchs-returns-fs-lemma-3
  (implies (and (consp fs) (l1-fs-p fs)
                (consp (assoc-equal s fs))
                (not (stringp (cdr (assoc-equal s fs)))))
           (l1-fs-p (cdr (assoc-equal s fs)))))

(defthm l1-wrchs-returns-fs
  (implies (and (symbol-listp hns) (l1-fs-p fs))
           (l1-fs-p (l1-wrchs hns fs start text)))
  :hints (("Subgoal *1/6''" :use (:instance l1-wrchs-returns-fs-lemma-3 (s (car hns)))) ))

(defthm l1-unlink-returns-fs
  (implies (and (l1-fs-p fs))
           (l1-fs-p (l1-unlink hns fs))))

(defthm l1-read-after-write-1-lemma-1
  (implies (consp (assoc-equal name alist))
           (equal (car (assoc-equal name alist)) name)))

(defthm l1-read-after-write-1-lemma-2
  (implies (and (l1-fs-p fs) (stringp text) (stringp (l1-stat hns fs)))
           (stringp (l1-stat hns (l1-wrchs hns fs start text)))))

(defthm l1-read-after-write-1-lemma-3
  (implies (l1-rdchs hns fs start n)
           (stringp (l1-stat hns fs))))

(defthm l1-read-after-write-1
  (implies (and (l1-fs-p fs)
                (stringp text)
                (symbol-listp hns)
                (natp start)
                (equal n (length text))
                (stringp (l1-stat hns fs)))
           (equal (l1-rdchs hns (l1-wrchs hns fs start text) start n) text)))

(defthm l1-read-after-write-2-lemma-1
  (implies (l1-fs-p fs)
           (not (stringp (assoc-equal name fs)))))

(defthm l1-read-after-write-2-lemma-2
  (implies (and (consp hns1)
                (consp fs)
                (consp (assoc-equal (car hns1) fs))
                (l1-fs-p fs)
                (symbolp (car hns1))
                (not (cdr hns1))
                (stringp (l1-stat hns1 fs)))
           (equal (l1-stat hns1 fs) (cdr (assoc (car hns1) fs)))))

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

  (defthm l1-read-after-write-2-lemma-3
    (implies (and (l1-fs-p fs)
                  (stringp text2)
                  (symbol-listp hns1)
                  (symbol-listp hns2)
                  (not (equal hns1 hns2))
                  (natp start2)
                  (stringp (l1-stat hns1 fs)))
             (equal (l1-stat hns1 (l1-wrchs hns2 fs start2 text2)) (l1-stat hns1 fs)))
    :hints (("Goal"  :induct (induction-scheme hns1 hns2 fs))
            ("Subgoal *1/7.1''" :in-theory (disable alistp-l1-fs-p)
             :use (:instance alistp-l1-fs-p (fs (l1-wrchs (cdr hns2)
                                                    (cdr (assoc-equal (car hns1) fs))
                                                    start2 text2))))))

  )

;; to be revisited - (stringp (l1-stat hns1 fs)) is not a necessary condition
;; but the proof doesn't go through without it
(defthm l1-read-after-write-2
  (implies (and (l1-fs-p fs)
                (stringp text2)
                (symbol-listp hns1)
                (symbol-listp hns2)
                (not (equal hns1 hns2))
                (natp start1)
                (natp start2)
                (natp n1)
                (stringp (l1-stat hns1 fs)))
           (equal (l1-rdchs hns1 (l1-wrchs hns2 fs start2 text2) start1 n1)
                  (l1-rdchs hns1 fs start1 n1))))

; Find length of file
(defun l1-wc-len (hns fs)
  (declare (xargs :guard (and (symbol-listp hns)
                              (l1-fs-p fs))))
  (let ((file (l1-stat hns fs)))
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

;; (assign fs '((a . "Mihir") (b . "Warren") (c (a . "Mehta") (b . "Hunt"))))

;; (assign h1 '(a))
;; (assign h2 '(a b))
;; (assign h3 '(c b))
;; (assign h4 '(c))

;; (l1-stat (@ h1) (@ fs))
;; (l1-stat (@ h2) (@ fs))
;; (l1-stat (@ h3) (@ fs))
;; (l1-stat (@ h4) (@ fs))

;; (l1-wc-len (@ h1) (@ fs))
;; (l1-wc-len (@ h2) (@ fs))
;; (l1-wc-len (@ h3) (@ fs))
;; (l1-wc-len (@ h4) (@ fs))

;; (l1-wrchs (@ h1) (@ fs) 1 "athur")
;; (l1-wrchs (@ h3) (@ fs) 1 "inojosa")
;; (l1-wrchs (@ h3) (@ fs) 5 "Alvarez")

;; (l1-unlink (@ h1) (@ fs))
;; (l1-unlink (@ h2) (@ fs))
;; (l1-unlink (@ h3) (@ fs))
;; (l1-unlink (@ h4) (@ fs))

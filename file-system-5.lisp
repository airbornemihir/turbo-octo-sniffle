(in-package "ACL2")

;  file-system-5.lisp                                  Mihir Mehta

; Here we build on model 4 to add permissions to the file system. We'll go with
; something simple: let users be defined by integers, and not belong to groups
; at this point. Thus, only read and write permissions exist, and they are
; limited to being on/off for the creating user, and on/off for others.

; This will have to begin with defining an aggregate to hold the contents of a
; regular file. I'm not changing anything about directories at this point.

; begin encapsulate

(include-book "file-system-4")

(defund l5-regular-file-entry-p (entry)
  (declare (xargs :guard t))
  (and (equal (len entry) 6)
       (nat-listp (car entry))
       (natp (cadr entry))
       (feasible-file-length-p (len (car entry)) (cadr entry))
       (booleanp (car (cddr entry)))
       (booleanp (cadr (cddr entry)))
       (booleanp (car (cddr (cddr entry))))
       (booleanp (cadr (cddr (cddr entry))))
       (natp (cddr (cddr (cddr entry))))))

(defund l5-regular-file-contents (entry)
  (declare (xargs :guard (l5-regular-file-entry-p entry)
                  :guard-hints (("Goal" :in-theory (enable l5-regular-file-entry-p)))))
  (car entry))

(defund l5-regular-file-length (entry)
  (declare (xargs :guard (l5-regular-file-entry-p entry)
                  :guard-hints (("Goal" :in-theory (enable l5-regular-file-entry-p)))))
  (cadr entry))

(defund l5-regular-file-user-read (entry)
  (declare (xargs :guard (l5-regular-file-entry-p entry)
                  :guard-hints (("Goal" :in-theory (enable l5-regular-file-entry-p)))))
  (car (cddr entry)))

(defund l5-regular-file-user-write (entry)
  (declare (xargs :guard (l5-regular-file-entry-p entry)
                  :guard-hints (("Goal" :in-theory (enable l5-regular-file-entry-p)))))
  (cadr (cddr entry)))

(defund l5-regular-file-other-read (entry)
  (declare (xargs :guard (l5-regular-file-entry-p entry)
                  :guard-hints (("Goal" :in-theory (enable l5-regular-file-entry-p)))))
  (car (cddr (cddr entry))))

(defund l5-regular-file-other-write (entry)
  (declare (xargs :guard (l5-regular-file-entry-p entry)
                  :guard-hints (("Goal" :in-theory (enable l5-regular-file-entry-p)))))
  (cadr (cddr (cddr entry))))

(defund l5-regular-file-user (entry)
  (declare (xargs :guard (l5-regular-file-entry-p entry)
                  :guard-hints (("Goal" :in-theory (enable l5-regular-file-entry-p)))))
  (cddr (cddr (cddr entry))))

(defund l5-make-regular-file
  (contents length user-read user-write other-read other-write user)
  (declare (xargs :guard
                  (and (nat-listp contents)
                       (natp length)
                       (feasible-file-length-p (len contents)
                                               length)
                       (booleanp user-read)
                       (booleanp user-write)
                       (booleanp other-read)
                       (booleanp other-write)
                       (natp user))))
  (list* contents length user-read user-write other-read other-write user))

(defthm
  l5-make-regular-file-correctness-1
  (implies (and (nat-listp contents)
                (natp length)
                (feasible-file-length-p (len contents)
                                        length)
                (booleanp user-read)
                (booleanp user-write)
                (booleanp other-read)
                (booleanp other-write)
                (natp user))
           (l5-regular-file-entry-p
            (l5-make-regular-file contents length user-read user-write
                                  other-read other-write user)))
  :hints (("goal" :in-theory (enable l5-regular-file-entry-p
                                     l5-make-regular-file))))

(defthm
  l5-regular-file-entry-p-correctness-1
  (implies (l5-regular-file-entry-p entry)
           (and (nat-listp (l5-regular-file-contents entry))
                (natp (l5-regular-file-length entry))
                (feasible-file-length-p (len (l5-regular-file-contents entry))
                                        (l5-regular-file-length entry))
                (booleanp (l5-regular-file-user-read entry))
                (booleanp (l5-regular-file-user-write entry))
                (booleanp (l5-regular-file-other-read entry))
                (booleanp (l5-regular-file-other-write entry))
                (natp (l5-regular-file-user entry))))
  :hints (("goal" :in-theory (enable l5-regular-file-entry-p
                                     l5-regular-file-contents
                                     l5-regular-file-length
                                     l5-regular-file-user-read
                                     l5-regular-file-user-write
                                     l5-regular-file-other-read
                                     l5-regular-file-other-write
                                     l5-regular-file-user))))

(defthm l5-regular-file-entry-p-correctness-2
  (booleanp (l5-regular-file-entry-p entry))
  :hints (("goal" :in-theory (enable l5-regular-file-entry-p))))

; This function defines a valid filesystem. It's an alist where all the cars
; are symbols and all the cdrs are either further filesystems or regular files.
(defun l5-fs-p (fs)
  (declare (xargs :guard t))
  (if (atom fs)
      (null fs)
    (and (let ((directory-or-file-entry (car fs)))
           (if (atom directory-or-file-entry)
               nil
             (let ((name (car directory-or-file-entry))
                   (entry (cdr directory-or-file-entry)))
               (and (symbolp name)
                    (or (l5-regular-file-entry-p entry)
                        (l5-fs-p entry))))))
         (l5-fs-p (cdr fs)))))

(defthm l5-regular-file-entry-p-correctness-3
  (implies (l5-regular-file-entry-p entry)
           (not (l5-fs-p entry)))
  :hints (("Goal" :in-theory (enable l5-regular-file-entry-p)) )
  :rule-classes (:rewrite (:rewrite :corollary
                                    (implies (l5-fs-p entry)
                                             (not (l5-regular-file-entry-p entry))))))

(defthm alistp-l5-fs-p
  (implies (l5-fs-p fs)
           (alistp fs)))

(defthm l5-fs-p-assoc
  (implies (and (l5-fs-p fs)
                (consp (assoc-equal name fs))
                (not (l5-regular-file-entry-p (cdr (assoc-equal name fs)))))
           (l5-fs-p (cdr (assoc-equal name fs)))))

(defun l5-regular-file-readable-p (entry user)
  (declare (xargs :guard (l5-regular-file-entry-p entry)))
  (if (equal (l5-regular-file-user entry) user)
      (l5-regular-file-user-read entry)
    (l5-regular-file-other-read entry)))

;; This function allows a file or directory to be found in a filesystem given a
;; path.
;; Important change from l4: we are now returning the file object, rather than
;; the text contents of the file. Without this, stating the stat correctness
;; theorems will be pretty close to impossible.
(defun l5-stat (hns fs disk user)
  (declare (xargs :guard (and (symbol-listp hns)
                              (l5-fs-p fs)
                              (block-listp disk)
                              (natp user))))
  (if (atom hns)
      fs
    (if (atom fs)
        nil
      (let ((sd (assoc (car hns) fs)))
        (if (atom sd)
            nil
          (if (l5-regular-file-entry-p (cdr sd))
              (and (null (cdr hns))
                   (cdr sd))
            (l5-stat (cdr hns) (cdr sd) disk user)))))))

(defun l5-regular-file-writable-p (entry user)
  (declare (xargs :guard (l5-regular-file-entry-p entry)))
  (if (equal (l5-regular-file-user entry) user)
      (l5-regular-file-user-write entry)
    (l5-regular-file-other-write entry)))

;; This function finds a text file given its path and reads a segment of
;; that text file.
(defun l5-rdchs (hns fs disk start n user)
  (declare (xargs :guard (and (symbol-listp hns)
                              (l5-fs-p fs)
                              (natp start)
                              (natp n)
                              (block-listp disk)
                              (natp user))))
  (let ((file (l5-stat hns fs disk user)))
    (if (or (not (l5-regular-file-entry-p file)) 
            (not (l5-regular-file-readable-p file user)))
        nil
      (let* ((file-text 
              (coerce
               (unmake-blocks (fetch-blocks-by-indices
                               disk
                               (l5-regular-file-contents file))
                              (l5-regular-file-length file))
               'string))
             (file-length (length file-text))
             (end (+ start n)))
        (if (< file-length end)
            nil
          (subseq file-text start (+ start n)))))))

(defun l5-wrchs (hns fs disk alv start text user)
  (declare (xargs :guard (and (symbol-listp hns)
                              (l5-fs-p fs)
                              (natp start)
                              (stringp text)
                              (block-listp disk)
                              (boolean-listp alv)
                              (equal (len alv) (len disk)))
                  :guard-debug t))
  (if (atom hns)
      (mv fs disk alv) ;; error - showed up at fs with no name  - so leave fs unchanged
    (if (atom fs)
        (mv nil disk alv) ;; error, so leave fs unchanged
      (let ((sd (assoc (car hns) fs)))
        (if (atom sd)
            (mv fs disk alv) ;; file-not-found error, so leave fs unchanged
          (let ((contents (cdr sd)))
            (if (l5-regular-file-entry-p (cdr sd))
                (if (or (cdr hns) (not (l5-regular-file-writable-p (cdr sd) user)))
                    (mv (cons (cons (car sd) (cdr sd))
                              (delete-assoc (car hns) fs))
                        disk
                        alv) ;; error, so leave fs unchanged
                  (let* ((old-text
                          (unmake-blocks
                           (fetch-blocks-by-indices disk (l5-regular-file-contents (cdr sd)))
                           (l5-regular-file-length (cdr sd))))
                         (alv-after-free
                          (set-indices-in-alv alv (l5-regular-file-contents (cdr sd)) nil))
                         (new-text (insert-text old-text start text))
                         (new-blocks (make-blocks new-text))
                         (new-indices
                          (find-n-free-blocks alv-after-free (len new-blocks))))
                    (if (not (equal (len new-indices) (len new-blocks)))
                        ;; we have an error because of insufficient disk space
                        ;; - so we leave the fs unchanged
                        (mv (cons (cons (car sd) contents)
                                  (delete-assoc (car hns) fs))
                            disk
                            alv)
                      (mv (cons (cons (car sd)
                                      (cons new-indices (len new-text)))
                                (delete-assoc (car hns) fs))
                          ;; this (take) means we write as many blocks as we can
                          ;; if we run out of space
                          (set-indices disk new-indices new-blocks)
                          (set-indices-in-alv alv-after-free new-indices t)))))
              (mv-let (new-contents new-disk new-alv)
                (l5-wrchs (cdr hns) contents disk alv start text user)
                (mv (cons (cons (car sd) new-contents)
                          (delete-assoc (car hns) fs))
                    new-disk
                    new-alv)))
            ))))))

(defun l5-to-l4-fs (fs)
    (declare (xargs :guard (l5-fs-p fs)))
  (if (atom fs)
      nil
    (cons (let ((directory-or-file-entry (car fs)))
           (let ((name (car directory-or-file-entry))
                 (entry (cdr directory-or-file-entry)))
             (if (l5-regular-file-entry-p entry)
                 (list* name
                        (l5-regular-file-contents entry)
                        (l5-regular-file-length entry))
               (cons name (l5-to-l4-fs entry)))))
         (l5-to-l4-fs (cdr fs)))))

;; change the storage of this thing!
(defthm
  l5-to-l4-fs-correctness-1
  (implies (l5-fs-p fs)
           (l3-fs-p (l5-to-l4-fs fs)))
  :rule-classes
  (:rewrite
   (:rewrite :corollary (implies (l5-fs-p fs)
                                 (l4-fs-p (l5-to-l4-fs fs)))))
  :hints (("goal" :in-theory (enable l3-regular-file-entry-p))))

(defthm l5-stat-correctness-1-lemma-1
  (implies (and (l5-fs-p fs)
                (consp (assoc-equal name fs)))
           (consp (assoc-equal name (l5-to-l4-fs fs)))))

(defthm l5-stat-correctness-1-lemma-2
  (implies (and (consp fs))
           (consp (l5-to-l4-fs fs))))

(defthm l5-stat-correctness-1-lemma-3
  (implies
   (and (consp (assoc-equal name fs))
        (l5-regular-file-entry-p (cdr (assoc-equal name fs)))
        (l5-fs-p fs))
   (and (consp (assoc-equal name (l5-to-l4-fs fs)))
        (l3-regular-file-entry-p (cdr (assoc-equal name (l5-to-l4-fs fs))))
        (equal (cadr (assoc-equal name
                                  (l5-to-l4-fs fs)))
               (l5-regular-file-contents (cdr (assoc-equal name fs))))
        (equal (cddr (assoc-equal name
                                  (l5-to-l4-fs fs)))
               (l5-regular-file-length (cdr (assoc-equal name fs))))))
  :hints (("goal" :in-theory (enable l3-regular-file-entry-p)) ))

(defthm l5-stat-correctness-1-lemma-4
  (implies (and (l5-fs-p fs)
                (l5-fs-p (cdr (assoc-equal name fs))))
           (equal (cdr (assoc-equal name (l5-to-l4-fs fs)))
                  (l5-to-l4-fs (cdr (assoc-equal name fs))))))

;; This is the first of two theorems showing the equivalence of the l5 and l4
;; versions of stat.
(defthm
  l5-stat-correctness-1
  (implies
   (and (symbol-listp hns)
        (l5-fs-p fs)
        (block-listp disk))
   (let
    ((file (l5-stat hns fs disk user)))
    (implies
     (and (l5-regular-file-entry-p file)
          (l5-regular-file-readable-p file user)
          (natp user))
     (equal
      (l4-stat hns (l5-to-l4-fs fs) disk)
      (coerce
       (unmake-blocks
        (fetch-blocks-by-indices disk (l5-regular-file-contents file))
        (l5-regular-file-length file))
       'string))))))

(defthm
  l5-stat-correctness-2-lemma-1
  (implies
   (and (consp (assoc-equal name (l5-to-l4-fs fs)))
        (l5-fs-p fs)
        (l5-regular-file-entry-p (cdr (assoc-equal name fs))))
   (l3-regular-file-entry-p (cdr (assoc-equal name (l5-to-l4-fs fs)))))
  :hints (("goal" :in-theory (enable l3-regular-file-entry-p))))

;; This is the second of two theorems showing the equivalence of the l3 and l2
;; versions of stat.
(defthm l5-stat-correctness-2
  (implies (and (symbol-listp hns)
                (l5-fs-p fs)
                (block-listp disk)
                (natp user)
                (l5-fs-p (l5-stat hns fs disk user)))
           (equal (l4-stat hns (l5-to-l4-fs fs) disk)
                  (l5-to-l4-fs (l5-stat hns fs disk user) )))
  )

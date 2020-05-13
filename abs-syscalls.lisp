;  abs-syscalls.lisp                                    Mihir Mehta

; This is a model of the FAT32 filesystem, related to HiFAT but with abstract
; variables.

(in-package "ACL2")

(include-book "abs-find-file")
(include-book "hifat-syscalls")
(local (include-book "std/lists/prefixp" :dir :system))

(local (in-theory (e/d (abs-file-p-when-m1-regular-file-p)
                       nil)))

;; Let's try to do this intuitively first...

(defund
  abs-place-file (frame pathname file)
  (declare
   (xargs :guard (and (frame-p frame)
                      (fat32-filename-list-p pathname))
          :guard-debug t
          :guard-hints (("Goal" :do-not-induct t) )
          :verify-guards nil))
  (b*
      (((when (atom frame))
        (mv frame *enoent*))
       (pathname (mbe :exec pathname
                      :logic (fat32-filename-list-fix pathname)))
       ((mv tail tail-error-code)
        (abs-place-file (cdr frame) pathname file))
       ((unless (and (equal tail-error-code *ENOENT*)
                     (prefixp (frame-val->path (cdar frame))
                              pathname)))
        (mv (list* (car frame) tail) tail-error-code))
       ;; Look up the parent directory - it has to be in one of the variables,
       ;; or else we must return ENOENT.
       ((mv & error-code)
        (abs-find-file-helper
         (frame-val->dir (cdar frame))
         (nthcdr (len (frame-val->path (cdar frame)))
                 (butlast 1 pathname))))
       ((when (or (equal error-code *enoent*)
                  (not (abs-complete (frame-val->dir (cdar frame))))))
        (mv (list* (car frame) tail) tail-error-code))
       ((mv head head-error-code)
        (hifat-place-file (frame-val->dir (cdar frame)) pathname file)))
    (mv
     (list* (cons (caar frame) (change-frame-val (cdar frame) :dir head))
            (cdr frame))
     head-error-code)))

;; Move later.
(defthm intersectp-of-cons-2
  (iff (intersectp-equal x1 (cons x2 y))
       (or (member-equal x2 x1)
           (intersectp-equal y x1)))
  :hints (("goal" :in-theory (e/d (intersectp-equal)
                                  (intersectp-is-commutative))
           :expand (:with intersectp-is-commutative
                          (intersectp-equal x1 (cons x2 y))))))

(defund
  pathname-clear (pathname frame)
  (declare (xargs :guard (and (fat32-filename-list-p pathname)
                              (frame-p frame))
                  :guard-debug t))
  (b*
      (((when (atom frame)) t)
       ((unless
            (pathname-clear pathname (cdr frame)))
        nil)
       (pathname (mbe :exec pathname :logic (fat32-filename-list-fix
                                             pathname))))
    (and
     (or
      (not (prefixp
            pathname
            (frame-val->path (cdar frame))))
      (equal
       (frame-val->path (cdar frame))
       pathname))
     (or
      (not (prefixp
            (frame-val->path (cdar frame))
            pathname))
      (atom
       (names-at (frame-val->dir (cdar frame))
                 (nthcdr
                  (len (frame-val->path (cdar frame)))
                  pathname)))))))

(defthm
  dist-names-when-pathname-clear
  (implies (pathname-clear pathname frame)
           (dist-names dir pathname frame))
  :hints (("goal" :in-theory (enable dist-names
                                     pathname-clear prefixp intersectp-equal)
           :induct (pathname-clear pathname frame)
           :expand (dist-names dir pathname frame))))

;; I'm not even sure what the definition of abs-place-file above should be. But
;; I'm pretty sure it should support a theorem like the following.
;;
;; In the hypotheses here, there has to be a stipulation that not only is dir
;; complete, but also that it's the only one which has any names at that
;; particular relpath, i.e. (butlast 1 pathname). It's going to be a natural
;; outcome of partial-collapse, but it may have to be codified somehow.
(thm
 (implies
  (and
   ;; Guard of hifat-place-file.
   (and (m1-file-alist-p fs)
        (hifat-no-dups-p fs)
        (fat32-filename-list-p pathname)
        (m1-regular-file-p file)
        (abs-fs-p dir)
        (abs-complete dir)
        (pathname-clear (butlast 1 pathname) frame)
        (atom (names-at root (butlast 1 pathname))))
   (mv-nth 1 (collapse (frame-with-root
                        root
                        (cons
                         (cons
                          x
                          (frame-val
                           (butlast 1 pathname)
                           dir
                           src))
                         frame))))
   (absfat-equiv (mv-nth 0 (collapse (frame-with-root
                                      root
                                      (cons
                                       (cons
                                        x
                                        (frame-val
                                         (butlast 1 pathname)
                                         dir
                                         src))
                                       frame))))
                 fs)
   (abs-separate (frame-with-root
                  root
                  (cons
                   (cons
                    x
                    (frame-val
                     (butlast 1 pathname)
                     dir
                     src))
                   frame)))
   (not (member-equal (car (last pathname)) (names-at dir nil)))
   (consp pathname))
  (b*
      ((dir (put-assoc-equal (car (last pathname)) file dir))
       (frame (frame-with-root
               root
               (cons
                (cons
                 x
                 (frame-val
                  (butlast 1 pathname)
                  dir
                  src))
                frame)))
       ((mv fs error-code) (hifat-place-file fs pathname file)))
    (and
     (equal error-code 0)
     (mv-nth 1 (collapse frame))
     (absfat-equiv (mv-nth 0 (collapse frame))
                   fs)
     (abs-separate frame))))
 :hints (("Goal" :do-not-induct t
          :in-theory (enable dist-names abs-separate)))
 :otf-flg t)

(defthm
  frame-p-of-abs-place-file
  (implies (frame-p frame)
           (frame-p (mv-nth 0 (abs-place-file
                               frame
                               pathname
                               file))))
  :hints (("Goal" :in-theory (enable abs-place-file))))

(defund
  abs-remove-file (frame pathname)
  (declare
   (xargs :guard (and (frame-p frame)
                      (fat32-filename-list-p pathname))
          :guard-debug t
          :guard-hints (("Goal" :do-not-induct t) )
          :verify-guards nil))
  (b*
      (((when (atom frame))
        (mv frame *enoent*))
       (pathname (mbe :exec pathname
                      :logic (fat32-filename-list-fix pathname)))
       ((mv tail tail-error-code)
        (abs-remove-file (cdr frame) pathname))
       ((unless (and (equal tail-error-code *ENOENT*)
                     (prefixp (frame-val->path (cdar frame))
                              pathname)))
        (mv (list* (car frame) tail) tail-error-code))
       ;; Look up the parent directory - it has to be in one of the variables,
       ;; or else we must return ENOENT.
       ((mv & error-code)
        (abs-find-file-helper
         (frame-val->dir (cdar frame))
         (nthcdr (len (frame-val->path (cdar frame)))
                 (butlast 1 pathname))))
       ((when (or (equal error-code *enoent*)
                  (not (abs-complete (frame-val->dir (cdar frame))))))
        (mv (list* (car frame) tail) tail-error-code))
       ((mv head head-error-code)
        (hifat-remove-file (frame-val->dir (cdar frame)) pathname)))
    (mv
     (list* (cons (caar frame) (change-frame-val (cdar frame) :dir head))
            (cdr frame))
     head-error-code)))

(defund abs-mkdir
  (frame pathname)
  (b*
      ((frame (partial-collapse frame (butlast 1 pathname)))
       ;; After partial-collapse, either the parent directory is there in one
       ;; variable, or it isn't there at all.
       ((mv parent-dir error-code) (abs-find-file-helper (frame->root frame)
                                                         pathname))
       ((mv new-root &) (abs-remove-file (frame->root frame) pathname))
       ((unless (equal error-code 0))
        (mv frame -1 error-code))
       ((mv new-parent-dir error-code)
        (abs-place-file parent-dir pathname (make-abs-file :contents nil)))
       (frame (frame-with-root
               new-root
               (put-assoc-equal
                (find-new-index
                 ;; Using this, not (strip-cars (frame->frame frame)), to make
                 ;; sure we don't get a zero.
                 (strip-cars frame))
                new-parent-dir
                (frame->frame frame)))))
    (mv frame -1 error-code)))

(defthm abs-mkdir-correctness-lemma-1
  (implies (atom pathname)
           (equal (1st-complete-under-pathname frame pathname)
                  (1st-complete frame)))
  :hints (("goal" :in-theory (enable 1st-complete-under-pathname
                                     1st-complete prefixp))))

;; Move later.
(defthm true-listp-of-frame-with-root
  (equal (true-listp (frame-with-root root frame))
         (true-listp frame))
  :hints (("goal" :in-theory (enable frame-with-root))))
(defthm true-listp-of-put-assoc
  (implies (not (null name))
           (iff (true-listp (put-assoc-equal name val alist))
                (or (true-listp alist)
                    (atom (assoc-equal name alist))))))

(encapsulate
  ()

  (local
   (defthmd
     lemma
     (implies (and (mv-nth 1 (collapse frame))
                   (atom pathname)
                   (equal frame
                          (frame-with-root (frame->root frame)
                                           (frame->frame frame))))
              (equal (partial-collapse frame pathname)
                     (frame-with-root (mv-nth 0 (collapse frame))
                                      nil)))
     :hints (("goal" :in-theory (enable partial-collapse collapse collapse-this)
              :induct (collapse frame)
              :expand (partial-collapse frame pathname)))))

  (defthm
    abs-mkdir-correctness-lemma-2
    (implies
     (and (mv-nth 1
                  (collapse (frame-with-root root frame)))
          (atom pathname)
          (atom (assoc-equal 0 frame))
          (frame-p frame))
     (equal (partial-collapse (frame-with-root root frame)
                              pathname)
            (frame-with-root (mv-nth 0
                                     (collapse (frame-with-root root frame)))
                             nil)))
    :hints (("goal" :use (:instance lemma
                                    (frame (frame-with-root root frame)))))))

;; (thm
;;  (b*
;;      (((mv fs result) (collapse (frame-with-root root frame))))
;;    (implies
;;     (and
;;      result
;;      (atom (assoc-equal 0 frame))
;;      (frame-p frame))
;;     (and (mv-nth 1 (collapse (mv-nth 0 (abs-mkdir (frame-with-root root frame)
;;                                                   pathname))))
;;          (absfat-equiv (mv-nth 0 (collapse (mv-nth 0 (abs-mkdir
;;                                                       (frame-with-root root
;;                                                                        frame)
;;                                                       pathname))))
;;                        (mv-nth 0 (hifat-mkdir fs pathname))))))
;;  :hints (("Goal" :in-theory (enable hifat-mkdir abs-mkdir collapse)
;;           :do-not-induct t)) :otf-flg t)

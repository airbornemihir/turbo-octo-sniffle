;  abs-syscalls.lisp                                    Mihir Mehta

; This is a model of the FAT32 filesystem, related to HiFAT but with abstract
; variables.

(in-package "ACL2")

(include-book "abs-find-file")
(include-book "hifat-syscalls")
(local (include-book "std/lists/prefixp" :dir :system))
(local (include-book "std/lists/intersectp" :dir :system))

(local (in-theory (e/d (abs-file-p-when-m1-regular-file-p
                        nat-listp-of-strip-cars-when-frame-p)
                       nil)))

;; Let's try to do this intuitively first...

(defund
  abs-place-file-helper (fs pathname file)
  (declare (xargs :guard (and (abs-file-alist-p fs)
                              (fat32-filename-list-p pathname)
                              (abs-file-p file))
                  :guard-debug t
                  :measure (acl2-count pathname)))
  (b*
      (((unless (consp pathname))
        (mv fs *enoent*))
       (name (fat32-filename-fix (car pathname)))
       (alist-elem (abs-assoc name fs))
       ((unless (consp alist-elem))
        (if (atom (cdr pathname))
            (mv (abs-put-assoc name file fs) 0)
            (mv fs *enotdir*)))
       ((when (and (not (abs-directory-file-p (cdr alist-elem)))
                   (or (consp (cdr pathname))
                       (abs-directory-file-p file))))
        (mv fs *enotdir*))
       ((when
         (not (or (abs-directory-file-p (cdr alist-elem))
                  (consp (cdr pathname))
                  (abs-directory-file-p file)
                  (and (atom alist-elem)
                       (>= (len fs) *ms-max-dir-ent-count*)))))
        (mv (abs-put-assoc name file fs) 0))
       ((when (and (atom alist-elem)
                   (>= (len fs) *ms-max-dir-ent-count*)))
        (mv fs *enospc*))
       ((mv new-contents error-code)
        (abs-place-file-helper
         (abs-file->contents (cdr alist-elem))
         (cdr pathname)
         file)))
    (mv (abs-put-assoc
         name
         (make-abs-file
          :dir-ent (abs-file->dir-ent (cdr alist-elem))
          :contents new-contents)
         fs)
        error-code)))

(defthm
  abs-file-alist-p-of-abs-place-file-helper
  (implies
   (and (abs-file-alist-p fs)
        (abs-file-p file))
   (abs-file-alist-p (mv-nth 0
                             (abs-place-file-helper fs pathname file))))
  :hints (("goal" :in-theory (enable abs-place-file-helper))))

(defund
  abs-place-file (frame pathname file)
  (declare
   (xargs :guard (and (frame-p frame)
                      (abs-file-p file)
                      (fat32-filename-list-p pathname))
          :guard-hints (("Goal" :do-not-induct t) )))
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
                 (butlast pathname 1))))
       ((when (or (equal error-code *enoent*)
                  (not (abs-complete (frame-val->dir (cdar frame))))))
        (mv (list* (car frame) tail) tail-error-code))
       ((mv head head-error-code)
        (abs-place-file-helper (frame-val->dir (cdar frame)) pathname file)))
    (mv
     (list* (cons (caar frame) (change-frame-val (cdar frame)
                                                 :dir (abs-fs-fix head)))
            (cdr frame))
     head-error-code)))

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

(defthm
  hifat-subsetp-of-put-assoc-1
  (implies
   (and (m1-file-alist-p x)
        (hifat-no-dups-p x)
        (stringp name))
   (equal
    (hifat-subsetp (put-assoc-equal name val x)
                   y)
    (and
     (hifat-subsetp (remove-assoc-equal name x)
                    y)
     (consp (assoc-equal name y))
     (or
      (and (not (m1-directory-file-p (cdr (assoc-equal name y))))
           (not (m1-directory-file-p val))
           (equal (m1-file->contents val)
                  (m1-file->contents (cdr (assoc-equal name y)))))
      (and (m1-directory-file-p (cdr (assoc-equal name y)))
           (m1-directory-file-p val)
           (hifat-subsetp (m1-file->contents val)
                          (m1-file->contents (cdr (assoc-equal name y)))))))))
  :hints (("goal" :in-theory (enable hifat-subsetp)
           :induct (mv (put-assoc-equal name val x)
                       (remove-assoc-equal name x)))))

(defthm hifat-subsetp-of-put-assoc-2
  (implies (and (m1-file-alist-p x)
                (hifat-subsetp x (remove-assoc-equal name y)))
           (hifat-subsetp x (put-assoc-equal name val y)))
  :hints (("goal" :in-theory (enable hifat-subsetp))))

(defthm hifat-subsetp-of-remove-assoc-1
  (implies (and (m1-file-alist-p x)
                (atom (assoc-equal name x))
                (hifat-subsetp x y))
           (hifat-subsetp x (remove-assoc-equal name y)))
  :hints (("goal" :in-theory (enable hifat-subsetp))))

(defthm hifat-subsetp-of-remove-assoc-2
  (implies (hifat-subsetp x y)
           (hifat-subsetp (remove-assoc-equal name x)
                          y))
  :hints (("goal" :in-theory (enable hifat-subsetp))))

(defthmd
  hifat-place-file-correctness-lemma-1
  (implies (and (m1-file-alist-p x)
                (m1-file-alist-p y)
                (hifat-no-dups-p x)
                (hifat-no-dups-p y)
                (hifat-subsetp x y)
                (hifat-subsetp y x)
                (or (hifat-no-dups-p (m1-file->contents file))
                    (m1-regular-file-p file)))
           (and
            (hifat-subsetp (mv-nth 0 (hifat-place-file y pathname file))
                           (mv-nth 0 (hifat-place-file x pathname file)))
            (equal (mv-nth 1 (hifat-place-file y pathname file))
                   (mv-nth 1 (hifat-place-file x pathname file)))))
  :hints (("goal" :in-theory (enable hifat-place-file hifat-subsetp))))

;; This isn't a congruence rule, so it may have to be left disabled...
(defthmd
  hifat-place-file-correctness-4
  (implies
   (and (hifat-equiv m1-file-alist2 m1-file-alist1)
        (or (hifat-no-dups-p (m1-file->contents file))
            (m1-regular-file-p file)))
   (and
    (equal (mv-nth 1
                   (hifat-place-file m1-file-alist2 pathname file))
           (mv-nth 1
                   (hifat-place-file m1-file-alist1 pathname file)))
    (hifat-equiv (mv-nth 0
                         (hifat-place-file m1-file-alist2 pathname file))
                 (mv-nth 0
                         (hifat-place-file m1-file-alist1 pathname file)))))
  :hints
  (("goal" :in-theory (enable hifat-place-file hifat-equiv)
    :use ((:instance (:rewrite hifat-place-file-correctness-lemma-1)
                     (x (hifat-file-alist-fix m1-file-alist2))
                     (file file)
                     (pathname pathname)
                     (y (hifat-file-alist-fix m1-file-alist1)))
          (:instance (:rewrite hifat-place-file-correctness-lemma-1)
                     (x (hifat-file-alist-fix m1-file-alist1))
                     (file file)
                     (pathname pathname)
                     (y (hifat-file-alist-fix m1-file-alist2))))
    :do-not-induct t)))

;; Probably tricky to get a refinement relationship (in the defrefinement
;; sense) between literally absfat-equiv and hifat-equiv. But we can still have
;; some kind of substitute...
(encapsulate
  ()

  (local
   (defthmd lemma
     (implies (and (m1-file-alist-p abs-file-alist1)
                   (m1-file-alist-p abs-file-alist2)
                   (hifat-no-dups-p abs-file-alist1)
                   (hifat-no-dups-p abs-file-alist2))
              (equal (absfat-equiv abs-file-alist1 abs-file-alist2)
                     (hifat-equiv abs-file-alist1 abs-file-alist2)))
     :hints (("goal" :in-theory (enable absfat-equiv hifat-equiv abs-fs-p
                                        absfat-subsetp-correctness-1)))))

  (defthm
    hifat-equiv-when-absfat-equiv
    (implies (and (m1-file-alist-p (abs-fs-fix abs-file-alist1))
                  (m1-file-alist-p (abs-fs-fix abs-file-alist2)))
             (equal (absfat-equiv abs-file-alist1 abs-file-alist2)
                    (hifat-equiv (abs-fs-fix abs-file-alist1)
                                 (abs-fs-fix abs-file-alist2))))
    :hints
    (("goal" :use (:instance lemma
                             (abs-file-alist1 (abs-fs-fix abs-file-alist1))
                             (abs-file-alist2 (abs-fs-fix abs-file-alist2)))))))

(defthm abs-fs-p-when-hifat-no-dups-p
  (implies (and (m1-file-alist-p fs)
                (hifat-no-dups-p fs))
           (abs-fs-p fs))
  :hints (("goal" :do-not-induct t
           :in-theory (enable abs-fs-p))))

;; Move later.
(defthm
  hifat-place-file-correctness-5
  (implies (hifat-no-dups-p (m1-file->contents file))
           (hifat-no-dups-p (mv-nth 0 (hifat-place-file fs pathname file))))
  :hints
  (("goal"
    :in-theory (enable hifat-place-file)
    :induct (hifat-place-file fs pathname file)
    :expand
    (:with
     (:rewrite hifat-no-dups-p-of-put-assoc)
     (hifat-no-dups-p
      (put-assoc-equal
       (fat32-filename-fix (car pathname))
       (m1-file
        (m1-file->dir-ent
         (cdr (assoc-equal (fat32-filename-fix (car pathname))
                           (hifat-file-alist-fix fs))))
        (mv-nth
         0
         (hifat-place-file
          (m1-file->contents
           (cdr (assoc-equal (fat32-filename-fix (car pathname))
                             (hifat-file-alist-fix fs))))
          (cdr pathname)
          file)))
       (hifat-file-alist-fix fs)))))))

(defthm
  absfat-place-file-correctness-lemma-3
  (implies
   (and
    (m1-file-alist-p fs)
    (hifat-no-dups-p fs)
    (abs-fs-p dir)
    (not (consp (abs-addrs dir)))
    (pathname-clear nil frame)
    (not (consp (names-at root nil)))
    (abs-fs-p root)
    (not (zp x))
    (not (consp (assoc-equal 0 frame)))
    (frame-p frame)
    (not (consp (assoc-equal x frame)))
    (no-duplicatesp-equal (strip-cars frame))
    (subsetp-equal
     (abs-addrs root)
     (frame-addrs-root
      (cons (cons x
                  (frame-val nil
                             (put-assoc-equal (car (last pathname))
                                              file dir)
                             src))
            frame)))
    (mv-nth 1
            (collapse (frame-with-root root
                                       (cons (cons x (frame-val nil dir src))
                                             frame))))
    (absfat-equiv
     (mv-nth 0
             (collapse (frame-with-root root
                                        (cons (cons x (frame-val nil dir src))
                                              frame))))
     fs)
    (no-duplicatesp-equal (abs-addrs root))
    (not (intersectp-equal nil (names-at dir nil)))
    (abs-separate frame))
   (hifat-equiv
    fs
    (mv-nth 0
            (collapse (frame-with-root root
                                       (cons (cons x (frame-val nil dir src))
                                             frame))))))
  :hints (("goal" :in-theory (enable abs-separate
                                     dist-names hifat-equiv-when-absfat-equiv
                                     frame-addrs-root))))

(defthm
  absfat-place-file-correctness-lemma-4
  (implies
   (subsetp-equal
    (abs-addrs root)
    (frame-addrs-root
     (cons (cons x
                 (frame-val nil
                            (put-assoc-equal (car (last pathname))
                                             file dir)
                            src))
           frame)))
   (subsetp-equal (abs-addrs root)
                  (frame-addrs-root (cons (cons x (frame-val 'nil dir src))
                                          frame))))
  :hints
  (("goal" :do-not-induct t
    :in-theory
    (e/d (hifat-equiv-when-absfat-equiv dist-names
                                        abs-separate frame-addrs-root)
         nil)))
  :otf-flg t)

(defthm
  absfat-place-file-correctness-lemma-5
  (implies
   (and
    (hifat-equiv
     (mv-nth
      0
      (collapse
       (frame-with-root
        root
        (cons (cons x
                    (frame-val nil
                               (put-assoc-equal (car (last pathname))
                                                file dir)
                               src))
              frame))))
     (mv-nth
      0
      (hifat-place-file
       fs nil
       (m1-file
        (m1-file->dir-ent
         (mv-nth
          0
          (hifat-find-file
           (mv-nth
            0
            (collapse (frame-with-root root
                                       (cons (cons x (frame-val nil dir src))
                                             frame))))
           nil)))
        (put-assoc-equal (car (last pathname))
                         file dir)))))
    (equal (mv-nth 1
                   (hifat-place-file fs nil
                                     (put-assoc-equal (car (last pathname))
                                                      file dir)))
           0))
   (hifat-equiv
    (mv-nth
     0
     (collapse
      (frame-with-root
       root
       (cons (cons x
                   (frame-val nil
                              (put-assoc-equal (car (last pathname))
                                               file dir)
                              src))
             frame))))
    (mv-nth 0 (hifat-place-file fs pathname file))))
  :instructions
  (:promote
   (:=
    (mv-nth
     0
     (collapse
      (frame-with-root
       root
       (cons (cons x
                   (frame-val nil
                              (put-assoc-equal (car (last pathname))
                                               file dir)
                              src))
             frame))))
    (mv-nth
     0
     (hifat-place-file
      fs nil
      (m1-file
       (m1-file->dir-ent
        (mv-nth
         0
         (hifat-find-file
          (mv-nth
           0
           (collapse (frame-with-root root
                                      (cons (cons x (frame-val nil dir src))
                                            frame))))
          nil)))
       (put-assoc-equal (car (last pathname))
                        file dir))))
    :equiv hifat-equiv)
   (:bash ("goal" :in-theory (enable hifat-place-file)))))

(defthm absfat-place-file-correctness-lemma-6
  (implies (and (abs-fs-p dir)
                (not (member-equal (car (last pathname))
                                   (names-at dir nil))))
           (not (consp (assoc-equal (car (last pathname))
                                    dir))))
  :hints (("goal" :in-theory (enable names-at))))

(defthm abs-file-p-when-m1-file-p
  (implies (m1-file-p file)
           (abs-file-p file))
  :hints (("goal" :cases ((abs-directory-file-p file)))))

(defthm
  m1-file-p-of-abs-file
  (equal (m1-file-p (abs-file dir-ent contents))
         (or (stringp (abs-file-contents-fix contents))
             (m1-file-alist-p contents)))
  :hints (("goal" :do-not-induct t
           :in-theory (enable m1-file-p abs-file abs-file-contents-fix
                              abs-file-contents-p
                              m1-file-contents-p))))

(defthm
  m1-file-alist-p-of-abs-place-file-helper
  (implies
   (and (m1-file-alist-p fs)
        (m1-file-p file))
   (m1-file-alist-p (mv-nth 0
                            (abs-place-file-helper fs pathname file))))
  :hints (("goal" :in-theory (enable abs-place-file-helper))))

(defthm
  abs-place-file-helper-correctness-1
  (implies (and (m1-file-alist-p fs)
                (hifat-no-dups-p fs)
                (m1-file-p file))
           (equal (abs-place-file-helper fs pathname file)
                  (hifat-place-file fs pathname file)))
  :hints (("goal" :in-theory (enable abs-place-file-helper
                                     hifat-place-file abs-file m1-file
                                     abs-file->dir-ent m1-file->dir-ent)
           :induct (abs-place-file-helper fs pathname file))))

(defthm
  abs-top-addrs-of-abs-place-file-helper
  (equal (abs-top-addrs (mv-nth 0
                                (abs-place-file-helper fs pathname file)))
         (abs-top-addrs fs))
  :hints (("goal" :in-theory (enable abs-top-addrs abs-place-file-helper))))

(defthm
  addrs-at-when-abs-complete
  (implies (abs-complete (abs-fs-fix fs))
           (equal (addrs-at fs relpath) nil))
  :hints
  (("goal" :in-theory (enable addrs-at)
    :induct (addrs-at fs relpath))
   ("subgoal *1/1''" :in-theory (disable ctx-app-ok-when-abs-complete-lemma-3)
    :use ctx-app-ok-when-abs-complete-lemma-3)))

(defthm
  addrs-at-of-abs-place-file-helper-lemma-1
  (implies (and (m1-file-p file)
                (or (m1-regular-file-p file)
                    (hifat-no-dups-p (m1-file->contents file))))
           (not (addrs-at (m1-file->contents file)
                          (cdr relpath))))
  :hints
  (("goal" :in-theory
    (e/d (m1-file-contents-p addrs-at m1-regular-file-p
                             m1-file-p m1-file->contents abs-fs-fix)
         (m1-file-contents-p-of-m1-file->contents))
    :use (:instance m1-file-contents-p-of-m1-file->contents
                    (x file))
    :do-not-induct t))
  :otf-flg t)

(defthm
  addrs-at-of-abs-place-file-helper-1
  (implies (and (abs-fs-p fs)
                (m1-file-p file)
                (or (m1-regular-file-p file)
                    (hifat-no-dups-p (m1-file->contents file))))
           (equal (addrs-at (mv-nth 0
                                    (abs-place-file-helper fs pathname file))
                            relpath)
                  (addrs-at fs relpath)))
  :hints
  (("goal"
    :in-theory (enable abs-place-file-helper addrs-at)
    :induct (mv (fat32-filename-list-prefixp relpath pathname)
                (addrs-at fs relpath))
    :expand
    ((abs-place-file-helper fs pathname file)
     (addrs-at
      (put-assoc-equal
       (fat32-filename-fix (car pathname))
       (abs-file
        (abs-file->dir-ent
         (cdr (assoc-equal (fat32-filename-fix (car pathname))
                           fs)))
        (mv-nth
         0
         (abs-place-file-helper
          (abs-file->contents
           (cdr (assoc-equal (fat32-filename-fix (car pathname))
                             fs)))
          (cdr pathname)
          file)))
       fs)
      relpath)))))

(defthm
  ctx-app-ok-of-abs-place-file-helper-1
  (implies
   (and (abs-fs-p fs)
        (m1-file-p file)
        (or (m1-regular-file-p file)
            (hifat-no-dups-p (m1-file->contents file))))
   (equal (ctx-app-ok (mv-nth 0
                              (abs-place-file-helper fs pathname file))
                      x x-path)
          (ctx-app-ok fs x x-path)))
  :hints (("goal" :in-theory (enable ctx-app-ok))))

(defthm natp-of-abs-place-file-helper
  (natp (mv-nth 1
                (abs-place-file-helper fs pathname file)))
  :hints (("goal" :in-theory (enable abs-place-file-helper)))
  :rule-classes :type-prescription)

(defthm
  collapse-hifat-place-file-lemma-9
  (implies
   (and (equal (frame->root frame1)
               (mv-nth 0
                       (abs-place-file-helper (frame->root frame2)
                                              pathname file)))
        (m1-file-p file)
        (or (m1-regular-file-p file)
            (hifat-no-dups-p (m1-file->contents file))))
   (equal
    (ctx-app-ok
     (frame->root frame1)
     (1st-complete (frame->frame frame1))
     (frame-val->path (cdr (assoc-equal (1st-complete (frame->frame frame1))
                                        (frame->frame frame1)))))
    (ctx-app-ok
     (frame->root frame2)
     (1st-complete (frame->frame frame1))
     (frame-val->path (cdr (assoc-equal (1st-complete (frame->frame frame1))
                                        (frame->frame frame1)))))))
  :hints
  (("goal"
    :in-theory (disable (:rewrite ctx-app-ok-of-abs-place-file-helper-1))
    :use
    (:instance
     (:rewrite ctx-app-ok-of-abs-place-file-helper-1)
     (x-path
      (frame-val->path (cdr (assoc-equal (1st-complete (frame->frame frame1))
                                         (frame->frame frame1)))))
     (x (1st-complete (frame->frame frame1)))
     (file file)
     (pathname pathname)
     (fs (frame->root frame2))))))

(defthm abs-place-file-helper-correctness-2
  (implies (not (zp (mv-nth 1
                            (abs-place-file-helper fs pathname file))))
           (equal (mv-nth 0
                          (abs-place-file-helper fs pathname file))
                  fs))
  :hints (("goal" :in-theory (enable abs-place-file-helper))))

(defthm natp-of-abs-place-file-helper
  (natp (mv-nth 1
                (abs-place-file-helper fs pathname file)))
  :hints (("goal" :in-theory (enable abs-place-file-helper)))
  :rule-classes :type-prescription)

(defthm names-at-of-abs-place-file-helper-lemma-1
  (implies (and (abs-file-p file)
                (not (abs-directory-file-p file)))
           (not (names-at (abs-file->contents file)
                          (nthcdr 1 relpath))))
  :hints (("goal" :in-theory (enable names-at abs-directory-file-p
                                     abs-file-p abs-file->contents
                                     abs-file-contents-p abs-fs-fix)
           :do-not-induct t)))

(defthm
  names-at-of-abs-place-file-helper-lemma-2
  (implies (m1-regular-file-p file)
           (not (names-at (m1-file->contents file)
                          (nthcdr 1 relpath))))
  :hints (("goal" :in-theory (enable names-at
                                     abs-directory-file-p m1-regular-file-p
                                     abs-file-p abs-file->contents
                                     abs-file-contents-p abs-fs-fix)
           :do-not-induct t)))

(defthm names-at-of-abs-place-file-helper-lemma-3
  (implies (and (abs-no-dups-p (abs-file->contents file))
                (abs-directory-file-p file))
           (abs-fs-p (abs-file->contents file)))
  :hints (("goal" :in-theory (enable abs-directory-file-p)
           :do-not-induct t)))

(defthm names-at-of-abs-place-file-helper-lemma-5
  (implies (m1-regular-file-p file)
           (equal (strip-cars (abs-fs-fix (m1-file->contents file)))
                  nil))
  :hints (("goal" :do-not-induct t
           :in-theory (enable m1-regular-file-p
                              abs-file-p abs-file->contents
                              abs-fs-fix abs-file-contents-p))))

;; (b* ((fs (list (cons (coerce (name-to-fat32-name (coerce "var" 'list)) 'string)
;;                      (make-abs-file))
;;                (cons (coerce (name-to-fat32-name (coerce
;;                                                   "tmp"
;;                                                   'list))
;;                              'string)
;;                      (make-abs-file
;;                       :contents (list
;;                                  (cons
;;                                   (coerce
;;                                    (name-to-fat32-name
;;                                     (coerce
;;                                      "pipe"
;;                                      'list))
;;                                    'string)
;;                                   (make-abs-file)))))))
;;      ((mv val &) (abs-place-file-helper fs (pathname-to-fat32-pathname
;;                                             (coerce "/tmp/hspid" 'list))
;;                                         (make-abs-file))))
;;   (list (names-at val
;;                   (pathname-to-fat32-pathname
;;                    (coerce
;;                     "/tmp"
;;                     'list)))
;;         (names-at fs
;;                   (pathname-to-fat32-pathname
;;                    (coerce
;;                     "/tmp"
;;                     'list)))))

(defthm
  names-at-of-abs-place-file-helper-1
  (implies (and (abs-fs-p fs)
                (abs-file-p file))
           (equal (names-at (mv-nth 0
                                    (abs-place-file-helper fs pathname file))
                            relpath)
                  (cond ((not
                          (zp (mv-nth 1
                                      (abs-place-file-helper fs pathname file))))
                         (names-at fs relpath))
                        ((fat32-filename-list-prefixp pathname relpath)
                         (names-at (abs-file->contents file)
                                   (nthcdr (len pathname) relpath)))
                        ((and (fat32-filename-list-equiv relpath (butlast
                                                                  pathname 1))
                              (not
                               (member-equal (fat32-filename-fix (car (last pathname)))
                                             (names-at fs relpath))))
                         (append (names-at fs relpath)
                                 (list (fat32-filename-fix (car (last pathname))))))
                        (t (names-at fs relpath)))))
  :hints
  (("goal"
    :in-theory (e/d (abs-place-file-helper names-at fat32-filename-list-fix)
                    ((:definition member-equal)
                     (:definition put-assoc-equal)
                     (:rewrite ctx-app-ok-when-absfat-equiv-lemma-3)
                     (:definition abs-complete)
                     (:rewrite hifat-find-file-correctness-1-lemma-1)
                     (:type-prescription assoc-equal-when-frame-p)
                     (:definition assoc-equal)
                     (:definition no-duplicatesp-equal)
                     (:type-prescription len-when-consp)
                     (:rewrite m1-file-alist-p-when-subsetp-equal)
                     (:rewrite subsetp-when-prefixp)))
    :induct (mv (fat32-filename-list-prefixp relpath pathname)
                (names-at fs relpath))
    :expand (abs-place-file-helper fs pathname file))))

(ENCAPSULATE
  ()

  (local
   (defun
     induction-scheme (frame1 frame2)
     (declare (xargs :verify-guards nil
                     :measure (len (frame->frame frame1))))
     (cond
      ((and
        (not (atom (frame->frame frame1)))
        (not (zp (1st-complete (frame->frame frame1))))
        (not
         (zp
          (frame-val->src
           (cdr (assoc-equal (1st-complete (frame->frame frame1))
                             (frame->frame frame1))))))
        (not
         (or
          (equal
           (frame-val->src
            (cdr
             (assoc-equal (1st-complete (frame->frame frame1))
                          (frame->frame frame1))))
           (1st-complete (frame->frame frame1)))
          (atom
           (assoc-equal
            (frame-val->src
             (cdr
              (assoc-equal (1st-complete (frame->frame frame1))
                           (frame->frame frame1))))
            (remove-assoc-equal
             (1st-complete (frame->frame frame1))
             (frame->frame frame1))))))
        (prefixp
         (frame-val->path
          (cdr
           (assoc-equal
            (frame-val->src
             (cdr
              (assoc-equal (1st-complete (frame->frame frame1))
                           (frame->frame frame1))))
            (remove-assoc-equal
             (1st-complete (frame->frame frame1))
             (frame->frame frame1)))))
         (frame-val->path
          (cdr (assoc-equal (1st-complete (frame->frame frame1))
                            (frame->frame frame1)))))
        (ctx-app-ok
         (frame-val->dir
          (cdr
           (assoc-equal
            (frame-val->src
             (cdr
              (assoc-equal (1st-complete (frame->frame frame1))
                           (frame->frame frame1))))
            (remove-assoc-equal
             (1st-complete (frame->frame frame1))
             (frame->frame frame1)))))
         (1st-complete (frame->frame frame1))
         (nthcdr
          (len
           (frame-val->path
            (cdr
             (assoc-equal
              (frame-val->src
               (cdr
                (assoc-equal (1st-complete (frame->frame frame1))
                             (frame->frame frame1))))
              (remove-assoc-equal
               (1st-complete (frame->frame frame1))
               (frame->frame frame1))))))
          (frame-val->path
           (cdr (assoc-equal (1st-complete (frame->frame frame1))
                             (frame->frame frame1)))))))
       (induction-scheme
        (collapse-this frame1
                       (1st-complete (frame->frame frame1)))
        (collapse-this frame2
                       (1st-complete (frame->frame frame2)))))
      ((and
        (not (atom (frame->frame frame1)))
        (not (zp (1st-complete (frame->frame frame1))))
        (zp
         (frame-val->src
          (cdr (assoc-equal (1st-complete (frame->frame frame1))
                            (frame->frame frame1)))))
        (ctx-app-ok
         (frame->root frame1)
         (1st-complete (frame->frame frame1))
         (frame-val->path
          (cdr (assoc-equal (1st-complete (frame->frame frame1))
                            (frame->frame frame1))))))
       (induction-scheme
        (collapse-this frame1
                       (1st-complete (frame->frame frame1)))
        (collapse-this frame2
                       (1st-complete (frame->frame frame2)))))
      (t (mv frame1 frame2)))))

  (skip-proofs
   (defthmd
     collapse-hifat-place-file-lemma-8
     (implies
      (and
       (equal (frame->frame frame1)
              (frame->frame frame2))
       (equal (frame->root frame1)
              (mv-nth 0
                      (abs-place-file-helper (frame->root frame2)
                                             pathname file)))
       (m1-file-p file)
       (or (m1-regular-file-p file)
           (hifat-no-dups-p (m1-file->contents file)))
       (dist-names (frame->root frame2)
                   nil (frame->frame frame2))
       (abs-separate (frame->frame frame2))
       (frame-p (frame->frame frame2))
       (no-duplicatesp-equal (strip-cars (frame->frame frame2))))
      (and
       (equal
        (mv-nth 0 (collapse frame1))
        (mv-nth
         0
         (abs-place-file-helper (mv-nth 0 (collapse frame2))
                                pathname file)))
       (equal (mv-nth 1 (collapse frame1))
              (mv-nth 1 (collapse frame2)))))
     :hints
     (("goal"
       :in-theory
       (e/d
        (collapse)
        ((:definition no-duplicatesp-equal)
         (:rewrite partial-collapse-correctness-lemma-24)
         (:definition assoc-equal)
         (:rewrite subsetp-when-prefixp)
         (:definition member-equal)
         (:rewrite
          abs-separate-of-frame->frame-of-collapse-this-lemma-8
          . 2)
         (:linear count-free-clusters-correctness-1)
         (:rewrite partial-collapse-correctness-lemma-28)
         (:rewrite nthcdr-when->=-n-len-l)
         (:rewrite strip-cars-of-frame->frame-of-collapse-this)
         (:definition len)
         (:definition integer-listp)
         (:rewrite ctx-app-ok-when-absfat-equiv-lemma-4)
         (:definition remove-equal)
         (:rewrite remove-when-absent)))
       :induct (induction-scheme frame1 frame2)
       :expand (collapse frame2))))))

;; This theorem asserts some things about applying abs-place-file-helper to
;; filesystem instances with holes...
(defthm
  collapse-hifat-place-file-1
  (implies
   (and
    (equal
     (frame->root (frame-with-root (mv-nth 0
                                           (hifat-place-file (abs-fs-fix root)
                                                             pathname file))
                                   frame))
     (mv-nth 0
             (abs-place-file-helper (frame->root (frame-with-root root frame))
                                    pathname file)))
    (m1-file-p file)
    (or (m1-regular-file-p file)
        (hifat-no-dups-p (m1-file->contents file)))
    (dist-names (frame->root (frame-with-root root frame))
                nil
                (frame->frame (frame-with-root root frame)))
    (abs-separate (frame->frame (frame-with-root root frame)))
    (frame-p (frame->frame (frame-with-root root frame)))
    (no-duplicatesp-equal
     (strip-cars (frame->frame (frame-with-root root frame)))))
   (and
    (equal
     (mv-nth
      0
      (collapse (frame-with-root (mv-nth 0
                                         (hifat-place-file (abs-fs-fix root)
                                                           pathname file))
                                 frame)))
     (mv-nth
      0
      (abs-place-file-helper (mv-nth 0
                                     (collapse (frame-with-root root frame)))
                             pathname file)))
    (equal
     (mv-nth
      1
      (collapse (frame-with-root (mv-nth 0
                                         (hifat-place-file (abs-fs-fix root)
                                                           pathname file))
                                 frame)))
     (mv-nth 1
             (collapse (frame-with-root root frame))))))
  :hints
  (("goal"
    :use
    (:instance
     (:rewrite collapse-hifat-place-file-lemma-8)
     (frame1 (frame-with-root (mv-nth 0
                                      (hifat-place-file (abs-fs-fix root)
                                                        pathname file))
                              frame))
     (frame2 (frame-with-root root frame))))))

;; This is based on collapse-hifat-place-file-2, which relies on the lemma
;; collapse-hifat-place-file-lemma-6. That lemma would probably have to be tweaked to
;; deal with all the pathname appending stuff, which I'm skipping over for now.
(skip-proofs
 (defthm
   collapse-hifat-place-file-2
   (implies
    (and
     (m1-file-p file)
     (or (m1-regular-file-p file)
         (hifat-no-dups-p (m1-file->contents file)))
     (dist-names (frame->root (frame-with-root root frame))
                 nil
                 (frame->frame (frame-with-root root frame)))
     (abs-separate (frame->frame (frame-with-root root frame)))
     (frame-p (frame->frame (frame-with-root root frame)))
     (no-duplicatesp-equal
      (strip-cars (frame->frame (frame-with-root root frame)))))
    (and
     (equal
      (mv-nth
       0
       (collapse
        (frame-with-root
         root
         (put-assoc-equal
          x
          (frame-val
           (frame-val->path (cdr (assoc-equal x frame)))
           (mv-nth
            0
            (abs-place-file-helper
             (frame-val->dir (cdr (assoc-equal x frame)))
             pathname file))
           (frame-val->src (cdr (assoc-equal x frame))))
          frame))))
      (mv-nth
       0
       (abs-place-file-helper
        (mv-nth 0
                (collapse (frame-with-root root frame)))
        (append (frame-val->path (cdr (assoc-equal x frame)))
                pathname)
        file)))
     (equal
      (mv-nth
       1
       (collapse
        (frame-with-root
         root
         (put-assoc-equal
          x
          (frame-val
           (frame-val->path (cdr (assoc-equal x frame)))
           (mv-nth
            0
            (abs-place-file-helper
             (frame-val->dir (cdr (assoc-equal x frame)))
             pathname file))
           (frame-val->src (cdr (assoc-equal x frame))))
          frame))))
      (mv-nth 1
              (collapse (frame-with-root root frame))))))))

;; I guess I should say that this function can only really do so much, and if
;; we try to use this in our proofs we'll kinda be back to representing
;; filesystem trees as... filesystem trees. When I say it can only do so much,
;; I mean that it can only help us do some refinement proofs, which will tie
;; lofat to hifat and hifat to absfat. Ultimately, I guess we'll want theorems
;; that use the collapse-equiv relation defined previously...
(defun frame-reps-fs
    (frame fs)
  (b*
      (((mv fs-equiv result) (collapse frame)))
    (and result
         (absfat-equiv fs-equiv fs)
         (abs-separate frame)
         (subsetp-equal
          (abs-addrs (frame->root frame))
          (frame-addrs-root (frame->frame frame))))))

(defcong absfat-equiv equal (frame-reps-fs frame fs) 2)

;; I'm not even sure what the definition of abs-place-file above should be. But
;; I'm pretty sure it should support a theorem like the following.
;;
;; In the hypotheses here, there has to be a stipulation that not only is dir
;; complete, but also that it's the only one which has any names at that
;; particular relpath, i.e. (butlast pathname 1). It's codified under
;; pathname-clear.
;;
;; Also, the use hints in this theorem are awkward but necessary - restrict
;; hints do not work because there's never a real chance for them to be
;; applied, or so :brr tells us.
;;
;; OK, so how do we develop a specification for abs-mkdir which we can actually
;; USE? Like, we would want to say that (abs-mkdir frame) is going to return a
;; new frame and an error code, and that error code will tell us whether to
;; expect an unchanged frame (modulo absfat-equiv) or a new frame with an
;; element right at the front representing the parent directory of the new
;; directory with the new directory inside it.
(defthm
  absfat-place-file-correctness-lemma-2
  (implies
   (and
    (m1-file-alist-p fs)
    (hifat-no-dups-p fs)
    (fat32-filename-list-p pathname)
    (m1-regular-file-p file)
    (abs-fs-p dir)
    (abs-complete dir)
    (pathname-clear (butlast pathname 1)
                    frame)
    (atom (names-at root (butlast pathname 1)))
    (abs-fs-p root)
    (not (zp x))
    (atom (assoc-equal 0 frame))
    (frame-p frame)
    (not (consp (assoc-equal x frame)))
    (no-duplicatesp-equal (strip-cars frame))
    (frame-reps-fs
     (frame-with-root root
                      (cons (cons x
                                  (frame-val (butlast pathname 1)
                                             dir src))
                            frame))
     fs)
    (not (member-equal (car (last pathname))
                       (names-at dir nil)))
    (consp pathname))
   (b* ((dir (put-assoc-equal (car (last pathname))
                              file dir))
        (frame (frame-with-root root
                                (cons (cons x
                                            (frame-val (butlast pathname 1)
                                                       dir src))
                                      frame)))
        ((mv fs &)
         (hifat-place-file fs pathname file)))
     (frame-reps-fs frame fs)))
  :hints
  (("goal"
    :do-not-induct t
    :in-theory
    (e/d (hifat-place-file dist-names
                           abs-separate frame-addrs-root)
         (collapse-hifat-place-file-2
          (:rewrite m1-file-alist-p-when-subsetp-equal)
          (:definition member-equal)
          (:rewrite len-of-remove-assoc-when-no-duplicatesp-strip-cars)
          (:linear len-of-remove-assoc-1)
          (:definition remove-assoc-equal)
          (:rewrite subsetp-trans)
          (:rewrite abs-addrs-of-put-assoc-lemma-2)
          (:rewrite ctx-app-ok-when-absfat-equiv-lemma-4)
          (:rewrite collapse-congruence-lemma-4)
          (:definition integer-listp)
          len-when-hifat-bounded-file-alist-p
          member-of-abs-addrs-when-natp
          (:linear position-equal-ac-when-member)
          (:rewrite absfat-equiv-implies-set-equiv-addrs-at-1-lemma-1)
          (:rewrite 1st-complete-of-put-assoc-lemma-1)
          (:definition hifat-file-alist-fix)
          (:rewrite hifat-find-file-correctness-1-lemma-1)
          (:type-prescription ctx-app-list-when-set-equiv-lemma-4)
          (:rewrite m1-directory-file-p-when-m1-file-p)
          (:rewrite abs-no-dups-p-of-put-assoc-equal)
          (:rewrite nthcdr-when->=-n-len-l)
          (:rewrite
           ctx-app-ok-when-absfat-equiv-lemma-3)
          (:type-prescription assoc-when-zp-len)
          (:definition take)
          (:rewrite take-of-len-free)
          (:rewrite take-of-too-many)
          (:definition true-listp)
          (:rewrite true-listp-when-string-list)
          (:definition string-listp)))
    :use
    ((:instance collapse-hifat-place-file-2
                (frame (cons (cons x
                                   (frame-val (butlast pathname 1)
                                              dir src))
                             frame))
                (pathname (last pathname)))
     (:instance
      (:rewrite hifat-place-file-correctness-4)
      (file file)
      (pathname pathname)
      (m1-file-alist2
       (mv-nth
        0
        (collapse
         (frame-with-root
          root
          (cons (cons x
                      (frame-val (take (+ -1 (len pathname)) pathname)
                                 dir src))
                frame)))))
      (m1-file-alist1 fs))))))

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
          :guard-hints (("Goal" :do-not-induct t) )))
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
                 (butlast pathname 1))))
       ((when (or (equal error-code *enoent*)
                  (not (abs-complete (frame-val->dir (cdar frame))))))
        (mv (list* (car frame) tail) tail-error-code))
       ((mv head head-error-code)
        (hifat-remove-file (frame-val->dir (cdar frame)) pathname)))
    (mv
     (list* (cons (caar frame) (change-frame-val (cdar frame) :dir head))
            (cdr frame))
     head-error-code)))

;; Move later.
(defthm frame-p-of-partial-collapse
  (implies (frame-p frame)
           (frame-p (partial-collapse frame pathname)))
  :hints (("goal" :in-theory (enable partial-collapse))))

(defund abs-disassoc (fs pathname new-index)
  (declare (xargs :guard
                  (and (fat32-filename-list-p pathname)
                       (abs-file-alist-p fs)
                       (natp new-index))
                  :verify-guards nil))
  (b*
      ((new-index
        (mbe :exec new-index :logic (nfix new-index)))
       (pathname
        (mbe :exec pathname :logic (fat32-filename-list-fix pathname)))
       ((when (atom pathname))
        (mv fs (list new-index)))
       (alist-elem (abs-assoc (car pathname) fs))
       ((when (or (atom alist-elem)
                  (not (abs-directory-file-p (cdr alist-elem)))))
        (mv nil fs))
       ((mv x y)
        (abs-disassoc
         (abs-file->contents (cdr alist-elem))
         (cdr pathname)
         new-index)))
    (mv x
        (abs-put-assoc
         (car pathname)
         (change-abs-file
          (cdr alist-elem)
          :contents
          y)
         fs))))

(defthm
  abs-file-alist-p-of-abs-disassoc-1
  (implies
   (abs-file-alist-p fs)
   (abs-file-alist-p (mv-nth 1 (abs-disassoc fs pathname new-index))))
  :hints (("Goal" :in-theory (enable abs-disassoc abs-file-alist-p)
           :induct (abs-disassoc fs pathname new-index))))

(defthm
  abs-file-alist-p-of-abs-disassoc-2
  (implies (abs-file-alist-p fs)
           (abs-file-alist-p (mv-nth 0
                                     (abs-disassoc fs pathname new-index))))
  :hints (("goal" :in-theory (enable abs-disassoc)
           :induct (abs-disassoc fs pathname new-index))))

(defthm
  abs-no-dups-p-of-abs-disassoc-1
  (implies (and (abs-file-alist-p fs)
                (abs-no-dups-p fs))
           (abs-no-dups-p (mv-nth 0
                                  (abs-disassoc fs pathname new-index))))
  :hints (("goal" :in-theory (enable abs-disassoc)
           :induct (abs-disassoc fs pathname new-index))))

(defthm
  abs-no-dups-p-of-abs-disassoc-2
  (implies (and (abs-file-alist-p fs)
                (abs-no-dups-p fs))
           (abs-no-dups-p (mv-nth 1
                                  (abs-disassoc fs pathname new-index))))
  :hints (("goal" :in-theory (enable abs-disassoc abs-no-dups-p)
           :induct (abs-disassoc fs pathname new-index))))

(defthm abs-fs-p-of-abs-disassoc-1
  (implies (abs-fs-p fs)
           (abs-fs-p (mv-nth 0
                             (abs-disassoc fs pathname new-index))))
  :hints (("goal" :in-theory (enable abs-fs-p))))

(defthm abs-fs-p-of-abs-disassoc-2
  (implies (abs-fs-p fs)
           (abs-fs-p (mv-nth 1
                             (abs-disassoc fs pathname new-index))))
  :hints (("goal" :in-theory (enable abs-fs-p))))

(verify-guards abs-disassoc)

(defthmd abs-disassoc-of-fat32-filename-list-fix
  (equal (abs-disassoc fs (fat32-filename-list-fix pathname)
                       new-index)
         (abs-disassoc fs pathname new-index))
  :hints (("goal" :in-theory (enable abs-disassoc))))

(defcong
  fat32-filename-list-equiv equal
  (abs-disassoc fs pathname new-index)
  2
  :hints
  (("goal"
    :use (abs-disassoc-of-fat32-filename-list-fix
          (:instance abs-disassoc-of-fat32-filename-list-fix
                     (pathname pathname-equiv))))))

(defthm abs-mkdir-guard-lemma-1
  (implies (consp (assoc-equal 0 frame))
           (consp (assoc-equal 0 (partial-collapse frame pathname))))
  :hints (("goal" :in-theory (enable partial-collapse))))

;; This deliberately follows an almost-identical induction scheme to
;; abs-find-file. It was going to be a part of that function, but that just led
;; to too many failures.
(defund
  abs-find-file-src (frame pathname)
  (declare
   (xargs :guard (and (frame-p frame)
                      (fat32-filename-list-p pathname))))
  (b*
      (((when (atom frame)) 0)
       (pathname (mbe :exec pathname
                      :logic (fat32-filename-list-fix pathname)))
       ((unless (prefixp (frame-val->path (cdar frame))
                         pathname))
        (abs-find-file-src (cdr frame) pathname))
       ((mv & error-code)
        (abs-find-file-helper
         (frame-val->dir (cdar frame))
         (nthcdr (len (frame-val->path (cdar frame)))
                 pathname)))
       ((when (not (equal error-code *enoent*)))
        (mbe :exec (caar frame) :logic (nfix (caar frame)))))
    (abs-find-file-src (cdr frame) pathname)))

(defthm
  abs-find-file-src-correctness-2
  (implies
   (and (frame-p frame)
        (no-duplicatesp-equal (strip-cars frame))
        (not (equal (mv-nth 1 (abs-find-file frame pathname))
                    *enoent*)))
   (and
    (consp (assoc-equal (abs-find-file-src frame pathname)
                        frame))
    (prefixp
     (frame-val->path (cdr (assoc-equal (abs-find-file-src frame pathname)
                                        frame)))
     (fat32-filename-list-fix pathname))
    (not
     (equal
      (mv-nth
       1
       (abs-find-file-helper
        (frame-val->dir (cdr (assoc-equal (abs-find-file-src frame pathname)
                                          frame)))
        (nthcdr (len (frame-val->path
                      (cdr (assoc-equal (abs-find-file-src frame pathname)
                                        frame))))
                pathname)))
      *enoent*))))
  :hints (("goal" :in-theory (enable abs-find-file abs-find-file-src)))
  :rule-classes
  ((:rewrite
    :corollary
    (implies
     (and (frame-p frame)
          (no-duplicatesp-equal (strip-cars frame))
          (not (equal (mv-nth 1 (abs-find-file frame pathname))
                      *enoent*)))
     (and
      (prefixp
       (frame-val->path (cdr (assoc-equal (abs-find-file-src frame pathname)
                                          frame)))
       (fat32-filename-list-fix pathname))
      (not
       (equal
        (mv-nth
         1
         (abs-find-file-helper
          (frame-val->dir (cdr (assoc-equal (abs-find-file-src frame pathname)
                                            frame)))
          (nthcdr
           (len (frame-val->path
                 (cdr (assoc-equal (abs-find-file-src frame pathname)
                                   frame))))
           pathname)))
        *enoent*)))))))

(encapsulate ()

  (local
   (defthm
     lemma
     (implies (not (zp (abs-find-file-src frame pathname)))
              (consp (assoc-equal (abs-find-file-src frame pathname)
                                  frame)))
     :hints (("goal" :in-theory (enable abs-find-file abs-find-file-src)))))

  (defthm
    abs-find-file-src-correctness-1
    (implies (consp (assoc-equal 0 frame))
             (consp (assoc-equal (abs-find-file-src frame pathname)
                                 frame)))
    :hints (("goal" :in-theory (enable abs-find-file abs-find-file-src)))
    :rule-classes
    ((:rewrite
      :corollary
      (implies (or (not (zp (abs-find-file-src frame pathname)))
                   (consp (assoc-equal 0 frame))
                   (and (frame-p frame)
                        (no-duplicatesp-equal (strip-cars frame))
                        (not (equal (mv-nth 1 (abs-find-file frame pathname))
                                    *enoent*))))
               (consp (assoc-equal (abs-find-file-src frame pathname)
                                   frame)))
      :hints
      (("goal" :in-theory (disable
                           abs-find-file-src-correctness-2)
        :use
        abs-find-file-src-correctness-2))))))

(defthmd
  abs-find-file-src-of-fat32-filename-list-fix
  (equal
   (abs-find-file-src frame (fat32-filename-list-fix pathname))
   (abs-find-file-src frame pathname))
  :hints (("Goal" :in-theory (enable abs-find-file-src))))

(defcong
  fat32-filename-list-equiv
  equal (abs-find-file-src frame pathname)
  2
  :hints
  (("goal"
    :use
    ((:instance abs-find-file-src-of-fat32-filename-list-fix
                (pathname pathname-equiv))
     abs-find-file-src-of-fat32-filename-list-fix))))

(defthm abs-mkdir-guard-lemma-2
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

(defthm alistp-of-frame-with-root
  (implies (frame-p frame)
           (alistp (frame-with-root root frame)))
  :hints (("goal" :in-theory (disable alistp-when-frame-p)
           :use (:instance alistp-when-frame-p
                           (x (frame-with-root root frame))))))

(defthm
  assoc-after-remove1-assoc-when-no-duplicatesp
  (implies (and (not (null name))
                (no-duplicatesp-equal (remove-equal nil (strip-cars alist))))
           (not (consp (assoc-equal name
                                    (remove1-assoc-equal name alist))))))

(defthm
  abs-mkdir-guard-lemma-3
  (implies (and (mv-nth 1 (collapse frame))
                (atom pathname)
                (equal frame
                       (frame-with-root (frame->root frame)
                                        (frame->frame frame))))
           (equal (partial-collapse frame pathname)
                  (frame-with-root (mv-nth 0 (collapse frame))
                                   nil)))
  :hints (("goal" :in-theory
           (e/d
            (partial-collapse collapse collapse-this)
            ((:definition no-duplicatesp-equal)
             (:rewrite
              partial-collapse-correctness-lemma-24)
             (:definition assoc-equal)
             (:rewrite subsetp-when-prefixp)
             (:definition member-equal)
             (:definition true-listp)
             (:rewrite put-assoc-equal-without-change . 2)
             abs-separate-of-frame->frame-of-collapse-this-lemma-8
             (:rewrite true-list-fix-when-true-listp)
             (:rewrite true-listp-when-string-list)
             (:definition string-listp)
             (:definition put-assoc-equal)
             (:rewrite remove-assoc-of-put-assoc)
             (:rewrite abs-fs-p-when-hifat-no-dups-p)
             (:definition remove-assoc-equal)
             (:definition remove-equal)
             (:rewrite fat32-filename-p-correctness-1)))
           :induct (collapse frame)
           :expand (partial-collapse frame pathname))))

(defthm
  abs-mkdir-guard-lemma-4
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
  :hints (("goal"
           :in-theory (disable abs-mkdir-guard-lemma-3)
           :use (:instance abs-mkdir-guard-lemma-3
                           (frame (frame-with-root root frame))))))

(defthm abs-mkdir-guard-lemma-5
  (implies (abs-no-dups-p fs)
           (no-duplicatesp-equal (remove-equal nil (strip-cars fs))))
  :hints (("goal" :in-theory (enable abs-no-dups-p))))

(defthm
  abs-mkdir-guard-lemma-6
  (implies
   (no-duplicatesp-equal (strip-cars frame))
   (no-duplicatesp-equal (strip-cars (partial-collapse frame pathname))))
  :hints (("goal" :in-theory (enable partial-collapse collapse-this))))

(defthm
  abs-mkdir-guard-lemma-7
  (implies
   (abs-directory-file-p (mv-nth 0 (abs-find-file-helper fs pathname)))
   (abs-no-dups-p
    (abs-file->contents (mv-nth 0 (abs-find-file-helper fs pathname)))))
  :hints (("goal" :in-theory (enable abs-find-file-helper))))

(defthm
  abs-mkdir-guard-lemma-8
  (implies
   (abs-directory-file-p (mv-nth 0 (abs-find-file frame pathname)))
   (abs-no-dups-p
    (abs-file->contents (mv-nth 0 (abs-find-file frame pathname)))))
  :hints (("goal" :in-theory (enable abs-find-file))))

;; OK, here's the plan for defining abs-mkdir. We can proooobably get rid of
;; abs-place-file and abs-remove-file, since those tasks are going to be
;; accomplished by first bringing the parent directory to the front and then
;; doing a put-assoc or a remove-assoc respectively.
(defund abs-mkdir (frame pathname)
  (declare (xargs
            :guard (and (frame-p frame)
                        (consp (assoc-equal 0 frame))
                        (fat32-filename-list-p pathname)
                        (no-duplicatesp-equal (strip-cars frame)))
            :guard-debug t
            :guard-hints
            (("goal"
              :in-theory (enable abs-find-file-helper abs-fs-p)))))
  (b*
      ((pathname (mbe :exec pathname :logic (fat32-filename-list-fix pathname)))
       (dirname (hifat-dirname pathname))
       (frame (partial-collapse frame dirname))
       ;; After partial-collapse, either the parent directory is there in one
       ;; variable, or it isn't there at all.
       ((mv parent-dir error-code) (abs-find-file frame dirname))
       ((unless (or (atom dirname)
                    (and (zp error-code)
                         (abs-directory-file-p parent-dir))))
        (mv frame -1 *enoent*))
       (src (abs-find-file-src frame dirname))
       (new-index (find-new-index
                   ;; Using this, not (strip-cars (frame->frame frame)), to make
                   ;; sure we don't get a zero.
                   (strip-cars frame)))
       ;; It's not even a matter of removing that thing - we need to leave a
       ;; body address in its place...
       ((mv var new-src-dir) (abs-disassoc
                              (frame-val->dir (cdr (assoc-equal src frame)))
                              (nthcdr
                               (len
                                (frame-val->path (cdr (assoc-equal src
                                                                   frame))))
                               dirname)
                              new-index))
       (frame (put-assoc-equal src
                               (change-frame-val (cdr (assoc-equal src frame))
                                                 :dir new-src-dir)
                               frame))
       ;; Check somewhere that (hifat-basename pathname) is not already present...
       ((when (consp (abs-assoc (hifat-basename pathname) var)))
        (mv frame -1 *eexist*))
       (new-var (abs-put-assoc (hifat-basename pathname)
                               (make-abs-file :contents nil
                                              :dir-ent
                                              (dir-ent-install-directory-bit
                                               (dir-ent-fix nil)
                                               t))
                               var))
       (frame (frame-with-root (frame->root frame)
                               (cons (cons new-index
                                           (frame-val dirname
                                                      new-var src))
                                     (frame->frame frame)))))
    (mv frame -1 error-code)))

;; An example demonstrating that both ways of doing mkdir work out the same:
(assert-event
 (equal
  (b*
      ((fs (list (cons (implode (name-to-fat32-name (explode "tmp")))
                       (make-m1-file :contents nil))))
       (frame (frame-with-root fs nil))
       (result1 (frame-reps-fs frame fs))
       ((mv frame & &) (abs-mkdir frame (pathname-to-fat32-pathname (explode "/tmp/docs"))))
       ((mv frame error-code result3)
        (abs-mkdir frame
                   (pathname-to-fat32-pathname (explode "/tmp/docs/pdf-docs"))))
       ((mv frame result4) (collapse frame)))
    (list (m1-file-alist-p fs) result1 error-code result3 frame
          result4))
  '(T
    T -1 0
    (("TMP        "
      (DIR-ENT 0 0 0 0 0 0 0 0 0 0 0 0
               0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
      (CONTENTS
       ("DOCS       "
        (DIR-ENT 0 0 0 0 0 0 0 0 0 0 0 16
                 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
        (CONTENTS
         ("PDF-DOCS   " (DIR-ENT 0 0 0 0 0 0 0 0 0 0 0 16
                                 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
          (CONTENTS)))))))
    T)))

(assert-event
 (equal
  (b*
      ((fs (list (cons (implode (name-to-fat32-name (explode "tmp")))
                       (make-m1-file :contents nil))))
       ((mv fs & &) (hifat-mkdir fs (pathname-to-fat32-pathname (explode "/tmp/docs"))))
       ((mv fs & &)
        (hifat-mkdir fs
                     (pathname-to-fat32-pathname (explode "/tmp/docs/pdf-docs")))))
    (list fs))
  '((("TMP        "
      (DIR-ENT 0 0 0 0 0 0 0 0 0 0 0 0
               0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
      (CONTENTS
       ("DOCS       "
        (DIR-ENT 0 0 0 0 0 0 0 0 0 0 0 16
                 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
        (CONTENTS
         ("PDF-DOCS   " (DIR-ENT 0 0 0 0 0 0 0 0 0 0 0 16
                                 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
          (CONTENTS))))))))))

(defthm
  abs-mkdir-correctness-lemma-1
  (implies
   (and
    (equal
     (frame-val->src
      (cdr (assoc-equal (1st-complete-under-pathname (frame->frame frame)
                                                     pathname)
                        (frame->frame frame))))
     0)
    (< 0
       (1st-complete-under-pathname (frame->frame frame)
                                    pathname))
    (no-duplicatesp-equal (abs-addrs (frame->root frame)))
    (not (consp (frame-val->path (cdr (assoc-equal 0 frame)))))
    (no-duplicatesp-equal (strip-cars (frame->frame frame)))
    (abs-separate frame))
   (abs-separate
    (collapse-this frame
                   (1st-complete-under-pathname (frame->frame frame)
                                                pathname))))
  :hints (("goal" :in-theory (enable collapse-this)
           :do-not-induct t)))

(defthm
  abs-mkdir-correctness-lemma-4
  (implies
   (and
    (< 0
       (1st-complete-under-pathname (frame->frame frame)
                                    pathname))
    (not
     (equal
      (frame-val->src
       (cdr (assoc-equal (1st-complete-under-pathname (frame->frame frame)
                                                      pathname)
                         (frame->frame frame))))
      (1st-complete-under-pathname (frame->frame frame)
                                   pathname)))
    (consp
     (assoc-equal
      (frame-val->src
       (cdr (assoc-equal (1st-complete-under-pathname (frame->frame frame)
                                                      pathname)
                         (frame->frame frame))))
      (frame->frame frame)))
    (prefixp
     (frame-val->path
      (cdr
       (assoc-equal
        (frame-val->src
         (cdr (assoc-equal (1st-complete-under-pathname (frame->frame frame)
                                                        pathname)
                           (frame->frame frame))))
        (frame->frame frame))))
     (frame-val->path
      (cdr (assoc-equal (1st-complete-under-pathname (frame->frame frame)
                                                     pathname)
                        (frame->frame frame)))))
    (ctx-app-ok
     (frame-val->dir
      (cdr
       (assoc-equal
        (frame-val->src
         (cdr (assoc-equal (1st-complete-under-pathname (frame->frame frame)
                                                        pathname)
                           (frame->frame frame))))
        (frame->frame frame))))
     (1st-complete-under-pathname (frame->frame frame)
                                  pathname)
     (nthcdr
      (len
       (frame-val->path
        (cdr
         (assoc-equal
          (frame-val->src
           (cdr (assoc-equal (1st-complete-under-pathname (frame->frame frame)
                                                          pathname)
                             (frame->frame frame))))
          (frame->frame frame)))))
      (frame-val->path
       (cdr (assoc-equal (1st-complete-under-pathname (frame->frame frame)
                                                      pathname)
                         (frame->frame frame))))))
    (no-duplicatesp-equal (abs-addrs (frame->root frame)))
    (not (consp (frame-val->path (cdr (assoc-equal 0 frame)))))
    (frame-p (frame->frame frame))
    (no-duplicatesp-equal (strip-cars (frame->frame frame)))
    (abs-separate frame))
   (abs-separate
    (collapse-this frame
                   (1st-complete-under-pathname (frame->frame frame)
                                                pathname))))
  :hints (("goal" :in-theory (enable collapse-this)
           :do-not-induct t)))

(defthm
  abs-mkdir-correctness-lemma-5
  (not
   (consp
    (frame-val->path
     (cdr
      (assoc-equal
       0
       (collapse-this frame
                      (1st-complete-under-pathname (frame->frame frame)
                                                   pathname)))))))
  :hints (("goal" :in-theory (enable collapse-this
                                     frame->root frame-with-root)
           :do-not-induct t)))

(defthm
  abs-mkdir-correctness-lemma-6
  (implies (and (no-duplicatesp-equal (abs-addrs (frame->root frame)))
                (atom (frame-val->path (cdr (assoc-equal 0 frame))))
                (frame-p (frame->frame frame))
                (no-duplicatesp-equal (strip-cars (frame->frame frame)))
                (abs-separate frame))
           (abs-separate (partial-collapse frame pathname)))
  :hints (("goal" :in-theory (enable partial-collapse))))

(defthm
  abs-mkdir-correctness-lemma-7
  (implies
   (and (frame-p (frame->frame frame))
        (no-duplicatesp-equal (strip-cars (frame->frame frame)))
        (abs-separate (frame-with-root (frame->root frame)
                                       (frame->frame frame)))
        (subsetp (abs-addrs (frame->root frame))
                 (frame-addrs-root (frame->frame frame))))
   (subsetp-equal
    (abs-addrs (frame->root (partial-collapse frame pathname)))
    (frame-addrs-root (frame->frame (partial-collapse frame pathname)))))
  :hints (("goal" :in-theory (enable partial-collapse)
           :induct (partial-collapse frame pathname))))

(defthm
  abs-mkdir-correctness-lemma-8
  (not (consp (assoc-equal (find-new-index (strip-cars alist))
                           alist)))
  :hints (("goal" :in-theory (disable member-of-strip-cars)
           :use (:instance member-of-strip-cars
                           (x (find-new-index (strip-cars alist))))))
  :rule-classes (:rewrite :type-prescription))

(defthm
  abs-mkdir-correctness-lemma-9
  (implies
   (consp (assoc-equal 0 alist))
   (not (equal (find-new-index (strip-cars alist)) 0)))
  :hints (("Goal" :in-theory
           (disable
            abs-mkdir-correctness-lemma-8)
           :use
           abs-mkdir-correctness-lemma-8))
  :rule-classes
  (:rewrite
   (:linear
    :corollary
    (implies
     (consp (assoc-equal 0 alist))
     (< 0 (find-new-index (strip-cars alist)))))
   (:type-prescription
    :corollary
    (implies
     (consp (assoc-equal 0 alist))
     (< 0 (find-new-index (strip-cars alist)))))))

(defthmd
  hifat-basename-dirname-helper-of-fat32-filename-list-fix
  (equal (hifat-basename-dirname-helper (fat32-filename-list-fix path))
         (hifat-basename-dirname-helper path))
  :hints (("goal" :in-theory (enable hifat-basename-dirname-helper))))

(defcong
  fat32-filename-list-equiv equal
  (hifat-basename-dirname-helper path)
  1
  :hints
  (("goal"
    :use
    ((:instance
      hifat-basename-dirname-helper-of-fat32-filename-list-fix
      (path path-equiv))
     hifat-basename-dirname-helper-of-fat32-filename-list-fix))))

(defcong
  fat32-filename-list-equiv equal
  (hifat-basename path)
  1
  :hints
  (("goal" :in-theory (enable hifat-basename))))

(defcong
  fat32-filename-list-equiv equal
  (hifat-dirname path)
  1
  :hints
  (("goal" :in-theory (enable hifat-dirname))))

(defthm
  abs-mkdir-correctness-lemma-10
  (implies
   (consp (assoc-equal 0 frame))
   (< 0
      (find-new-index
       (strip-cars (partial-collapse frame (hifat-dirname pathname))))))
  :hints (("goal" :in-theory (enable abs-mkdir
                                     hifat-mkdir collapse 1st-complete)
           :do-not-induct t))
  :rule-classes (:linear :rewrite))

(defthm abs-mkdir-correctness-lemma-11
  (equal (frame->root (put-assoc-equal 0 val frame))
         (frame-val->dir val))
  :hints (("goal" :do-not-induct t
           :in-theory (enable frame->root))))

(defthm
  addrs-at-of-abs-disassoc-1
  (implies
   (and (abs-fs-p fs) (natp new-index))
   (equal (addrs-at (mv-nth 1 (abs-disassoc fs pathname new-index))
                    relpath)
          (cond ((or (equal (mv-nth 1 (abs-disassoc fs pathname new-index))
                            fs)
                     (not (fat32-filename-list-prefixp pathname relpath)))
                 (addrs-at fs relpath))
                ((fat32-filename-list-equiv relpath pathname)
                 (list new-index))
                (t nil))))
  :hints
  (("goal"
    :in-theory (e/d (abs-top-addrs addrs-at
                                   abs-disassoc fat32-filename-list-fix
                                   abs-fs-p abs-file-alist-p abs-no-dups-p)
                    ((:rewrite abs-fs-p-correctness-1)
                     (:rewrite abs-no-dups-p-of-put-assoc-equal)
                     (:rewrite abs-fs-fix-of-put-assoc-equal-lemma-1)
                     (:rewrite abs-fs-p-when-hifat-no-dups-p)
                     (:rewrite hifat-find-file-correctness-1-lemma-1)
                     (:rewrite consp-of-assoc-of-abs-fs-fix)
                     (:rewrite abs-file->contents-when-m1-file-p)
                     (:rewrite subsetp-when-prefixp)))
    :induct (mv (fat32-filename-list-prefixp pathname relpath)
                (addrs-at fs relpath))
    :expand ((:free (fs) (addrs-at fs relpath))
             (abs-disassoc fs pathname new-index)))))

(defthm
  ctx-app-ok-of-abs-disassoc-1
  (implies (and (abs-fs-p fs)
                (natp new-index)
                ;; This clause becomes a test for pathname's existence...
                (not (equal (mv-nth 1 (abs-disassoc fs pathname new-index))
                            fs)))
           (ctx-app-ok (mv-nth 1 (abs-disassoc fs pathname new-index))
                       new-index pathname))
  :hints (("goal" :in-theory (enable ctx-app-ok))))

(defthm abs-mkdir-correctness-lemma-12
  (equal (frame->frame (put-assoc-equal 0 val frame))
         (frame->frame frame))
  :hints (("goal" :do-not-induct t
           :in-theory (enable frame->frame))))

;; Move later.
(defthm consp-of-assoc-of-frame->frame
  (implies (not (consp (assoc-equal x frame)))
           (not (consp (assoc-equal x (frame->frame frame)))))
  :hints (("goal" :in-theory (enable frame->frame))))

(defthm
  abs-mkdir-correctness-lemma-2
  (equal (frame-val->path (cdr (assoc-equal 0 (frame-with-root root frame))))
         nil)
  :hints (("goal" :in-theory (enable frame-with-root))))

(defthmd abs-mkdir-correctness-lemma-3
  (equal (assoc-equal x (frame-with-root root frame))
         (if (equal x 0)
             (cons 0 (frame-val nil (abs-fs-fix root) 0))
             (assoc-equal x frame)))
  :hints (("goal" :in-theory (enable frame-with-root))))

(defthmd abs-mkdir-correctness-lemma-13
  (equal (assoc-equal x (frame->frame frame))
         (if (not (equal x 0))
             (assoc-equal x frame)
             nil))
  :hints (("goal" :in-theory (enable frame->frame))))

(defthm
  abs-mkdir-correctness-lemma-14
  (implies (and (consp (assoc-equal 0 frame))
                (not (consp (assoc-equal x frame))))
           (not (consp (assoc-equal x (partial-collapse frame pathname)))))
  :hints (("goal" :in-theory (enable partial-collapse collapse-this
                                     abs-mkdir-correctness-lemma-3
                                     abs-mkdir-correctness-lemma-13)
           :induct (partial-collapse frame pathname))))

(defthm
  abs-mkdir-correctness-lemma-15
  (implies
   (and (equal (frame-val->path (cdr (assoc-equal 0 frame)))
               nil)
        (equal (frame-val->src (cdr (assoc-equal 0 frame)))
               0))
   (and
    (equal
     (frame-val->path (cdr (assoc-equal x (partial-collapse frame pathname))))
     (if (consp (assoc-equal x (partial-collapse frame pathname)))
         (frame-val->path (cdr (assoc-equal x frame)))
       nil))
    (equal
     (frame-val->src (cdr (assoc-equal x (partial-collapse frame pathname))))
     (if (consp (assoc-equal x (partial-collapse frame pathname)))
         (frame-val->src (cdr (assoc-equal x frame)))
       0))))
  :hints (("goal" :in-theory
           (e/d (partial-collapse collapse-this
                                  abs-mkdir-correctness-lemma-3
                                  abs-mkdir-correctness-lemma-13)
                ((:definition remove-assoc-equal)
                 (:rewrite remove-assoc-when-absent-1)
                 (:rewrite remove-assoc-of-put-assoc)
                 (:rewrite subsetp-when-prefixp)
                 (:rewrite abs-fs-fix-when-abs-fs-p)
                 (:rewrite abs-fs-p-when-hifat-no-dups-p)
                 (:definition member-equal)
                 (:definition abs-complete)
                 (:rewrite remove-assoc-of-remove-assoc)
                 (:definition len)))
           :induct (partial-collapse frame pathname))))

(defthmd
  abs-mkdir-correctness-lemma-16
  (implies (not (consp (hifat-dirname pathname)))
           (fat32-filename-list-equiv (hifat-dirname pathname)
                                      nil))
  :hints (("goal" :in-theory (enable hifat-dirname))))

(defthm abs-mkdir-correctness-lemma-17
  (implies (atom pathname)
           (equal (abs-find-file-src frame pathname)
                  0))
  :hints (("goal" :in-theory (enable abs-find-file-src
                                     abs-find-file-helper))))

(defthm
  abs-mkdir-correctness-lemma-18
  (implies
   (and (no-duplicatesp-equal (strip-cars frame))
        (frame-p frame)
        (equal (frame-val->src (cdr (assoc-equal 0 frame)))
               0)
        (not (consp (frame-val->path (cdr (assoc-equal 0 frame)))))
        (mv-nth 1 (collapse frame))
        (abs-separate frame)
        (subsetp-equal (abs-addrs (frame->root frame))
                       (frame-addrs-root (frame->frame frame))))
   (hifat-equiv
    (mv-nth 0
            (collapse (partial-collapse frame (hifat-dirname pathname))))
    (mv-nth 0 (collapse frame))))
  :hints
  (("goal" :in-theory (disable (:rewrite partial-collapse-correctness-1 . 1))
    :use (:instance (:rewrite partial-collapse-correctness-1 . 1)
                    (pathname (hifat-dirname pathname))
                    (frame frame)))))

(defthm
  abs-mkdir-correctness-lemma-19
  (implies
   (and
    (abs-directory-file-p
     (cdr (assoc-equal (car (fat32-filename-list-fix pathname))
                       fs)))
    (intersectp-equal
     y
     (abs-addrs
      (abs-file->contents
       (cdr (assoc-equal (car (fat32-filename-list-fix pathname))
                         fs))))))
   (intersectp-equal y (abs-addrs fs)))
  :instructions
  (:promote
   (:rewrite intersectp-is-commutative)
   (:rewrite
    intersect-with-subset
    ((x (abs-addrs
         (abs-file->contents
          (cdr (assoc-equal (car (fat32-filename-list-fix pathname))
                            fs)))))))
   :bash :bash))

(defthm
  abs-mkdir-correctness-lemma-20
  (implies
   (intersectp-equal
    y
    (abs-addrs (remove-assoc-equal (car (fat32-filename-list-fix pathname))
                                   fs)))
   (intersectp-equal y (abs-addrs fs)))
  :instructions
  (:promote
   (:rewrite intersectp-is-commutative)
   (:rewrite
    intersect-with-subset
    ((x
      (abs-addrs (remove-assoc-equal (car (fat32-filename-list-fix pathname))
                                     fs)))))
   :bash :bash))

(defthm
  abs-mkdir-correctness-lemma-21
  (implies
   (and (abs-fs-p fs)
        (natp new-index)
        (not (member-equal new-index y))
        (not (intersectp-equal y (abs-addrs fs))))
   (not (intersectp-equal
         y
         (abs-addrs (mv-nth 1
                            (abs-disassoc fs pathname new-index))))))
  :hints (("goal" :in-theory (enable abs-disassoc abs-addrs)
           :induct (abs-disassoc fs pathname new-index))))

(defthm
  abs-mkdir-correctness-lemma-22
  (implies
   (and (abs-directory-file-p (cdr (assoc-equal name fs)))
        (no-duplicatesp-equal (abs-addrs fs)))
   (not (intersectp-equal
         (abs-addrs (remove-assoc-equal name fs))
         (abs-addrs (abs-file->contents (cdr (assoc-equal name fs)))))))
  :hints (("goal" :in-theory (enable abs-addrs))))

(defthm
  abs-mkdir-correctness-lemma-23
  (implies (and (abs-fs-p fs)
                (natp new-index)
                (no-duplicatesp-equal (abs-addrs fs))
                (not (member-equal new-index (abs-addrs fs))))
           (no-duplicatesp-equal
            (abs-addrs (mv-nth 1
                               (abs-disassoc fs pathname new-index)))))
  :hints (("goal" :in-theory (enable abs-disassoc abs-addrs)
           :induct (abs-disassoc fs pathname new-index))))

(defthm
  abs-mkdir-correctness-lemma-24
  (ctx-app-ok
   (list (find-new-index
          (strip-cars (partial-collapse frame (hifat-dirname pathname)))))
   (find-new-index
    (strip-cars (partial-collapse frame (hifat-dirname pathname))))
   nil)
  :hints (("goal" :in-theory (enable ctx-app-ok addrs-at abs-fs-fix)
           :do-not-induct t)))

(defthm
  names-at-of-abs-disassoc-1
  (implies
   (and (abs-fs-p fs) (natp new-index))
   (equal (names-at (mv-nth 1 (abs-disassoc fs pathname new-index))
                    relpath)
          (cond ((or (equal (mv-nth 1 (abs-disassoc fs pathname new-index))
                            fs)
                     (not (fat32-filename-list-prefixp pathname relpath)))
                 (names-at fs relpath))
                (t nil))))
  :hints
  (("goal"
    :in-theory (e/d (abs-top-addrs names-at
                                   abs-disassoc fat32-filename-list-fix
                                   abs-fs-p abs-file-alist-p abs-no-dups-p)
                    ((:rewrite abs-fs-p-correctness-1)
                     (:rewrite abs-no-dups-p-of-put-assoc-equal)
                     (:rewrite abs-fs-fix-of-put-assoc-equal-lemma-1)
                     (:rewrite abs-fs-p-when-hifat-no-dups-p)
                     (:rewrite hifat-find-file-correctness-1-lemma-1)
                     (:rewrite consp-of-assoc-of-abs-fs-fix)
                     (:rewrite abs-file->contents-when-m1-file-p)
                     (:rewrite subsetp-when-prefixp)
                     (:rewrite remove-when-absent)
                     (:rewrite
                      absfat-equiv-implies-set-equiv-addrs-at-1-lemma-1)
                     (:definition remove-equal)
                     (:rewrite
                      m1-file-alist-p-of-cdr-when-m1-file-alist-p)
                     (:definition member-equal)
                     (:rewrite
                      abs-file-alist-p-when-m1-file-alist-p)
                     (:rewrite abs-file-alist-p-correctness-1)
                     (:rewrite abs-no-dups-p-when-m1-file-alist-p)
                     (:rewrite
                      abs-addrs-when-m1-file-alist-p-lemma-2)
                     (:rewrite abs-addrs-when-m1-file-alist-p)
                     (:rewrite member-of-abs-addrs-when-natp . 2)
                     (:rewrite member-of-abs-fs-fix-when-natp)
                     (:rewrite
                      abs-file-contents-p-when-m1-file-contents-p)
                     (:rewrite
                      fat32-filename-fix-when-fat32-filename-p)))
    :induct (mv (fat32-filename-list-prefixp pathname relpath)
                (names-at fs relpath))
    :expand ((:free (fs) (names-at fs relpath))
             (abs-disassoc fs pathname new-index)))))

(defthm dist-names-of-abs-disassoc-1
  (implies (and (abs-fs-p fs)
                (natp new-index)
                (dist-names fs relpath frame))
           (dist-names (mv-nth 1 (abs-disassoc fs pathname new-index))
                       relpath frame))
  :hints (("goal" :in-theory (enable dist-names))))

(defthm
  abs-find-file-correctness-lemma-16
  (implies
   (and
    (fat32-filename-list-prefixp x y)
    (zp (mv-nth 1 (abs-find-file-helper fs x)))
    (not
     (consp
      (abs-addrs
       (abs-file->contents (mv-nth 0 (abs-find-file-helper fs x)))))))
   (not (consp (addrs-at fs y))))
  :hints
  (("goal" :in-theory
    (e/d (abs-find-file-helper addrs-at fat32-filename-list-prefixp)
         (ctx-app-ok-when-abs-complete-lemma-4))
    :induct (mv (fat32-filename-list-prefixp x y)
                (mv-nth 0 (abs-find-file-helper fs x))))
   ("subgoal *1/1'''"
    :use
    (:instance
     ctx-app-ok-when-abs-complete-lemma-4
     (fs (abs-file->contents (cdr (assoc-equal (fat32-filename-fix (car x))
                                               (abs-fs-fix fs)))))
     (relpath (cdr y))))))

(defthm
  abs-mkdir-correctness-lemma-25
  (implies
   (and
    (equal (mv-nth 1
                   (abs-find-file-helper (frame->root frame)
                                         pathname))
           2)
    (prefixp
     (fat32-filename-list-fix pathname)
     (frame-val->path (cdr (assoc-equal (1st-complete (frame->frame frame))
                                        (frame->frame frame)))))
    (equal
     (mv-nth
      1
      (abs-find-file
       (remove-assoc-equal
        (frame-val->src (cdr (assoc-equal (1st-complete (frame->frame frame))
                                          (frame->frame frame))))
        (frame->frame frame))
       pathname))
     2)
    (ctx-app-ok
     (frame-val->dir
      (cdr
       (assoc-equal
        (frame-val->src (cdr (assoc-equal (1st-complete (frame->frame frame))
                                          (frame->frame frame))))
        (frame->frame frame))))
     (1st-complete (frame->frame frame))
     (nthcdr
      (len
       (frame-val->path
        (cdr (assoc-equal
              (frame-val->src
               (cdr (assoc-equal (1st-complete (frame->frame frame))
                                 (frame->frame frame))))
              (frame->frame frame)))))
      (frame-val->path (cdr (assoc-equal (1st-complete (frame->frame frame))
                                         (frame->frame frame))))))
    (frame-p frame)
    (no-duplicatesp-equal (strip-cars frame))
    (m1-regular-file-p (mv-nth 0 (abs-find-file frame pathname))))
   (consp (frame-val->path (cdr (assoc-equal 0 frame)))))
  :hints
  (("goal"
    :do-not-induct t
    :in-theory (e/d (fat32-filename-list-prefixp-alt ctx-app-ok)
                    (abs-find-file-correctness-lemma-16
                     abs-find-file-of-put-assoc-lemma-7
                     (:rewrite abs-addrs-when-m1-file-alist-p)
                     (:rewrite partial-collapse-correctness-lemma-24)
                     (:definition assoc-equal)
                     (:definition member-equal)
                     (:rewrite remove-when-absent)
                     (:definition remove-equal)
                     (:rewrite abs-file-alist-p-correctness-1)
                     (:rewrite abs-fs-p-when-hifat-no-dups-p)
                     (:rewrite prefixp-when-equal-lengths)
                     (:rewrite subsetp-when-prefixp)
                     (:definition no-duplicatesp-equal)))
    :use
    ((:instance
      abs-find-file-correctness-lemma-16
      (x
       (nthcdr
        (len
         (frame-val->path
          (cdr (assoc-equal
                (frame-val->src
                 (cdr (assoc-equal (1st-complete (frame->frame frame))
                                   (frame->frame frame))))
                (frame->frame frame)))))
        pathname))
      (y
       (nthcdr
        (len
         (frame-val->path
          (cdr (assoc-equal
                (frame-val->src
                 (cdr (assoc-equal (1st-complete (frame->frame frame))
                                   (frame->frame frame))))
                (frame->frame frame)))))
        (frame-val->path (cdr (assoc-equal (1st-complete (frame->frame frame))
                                           (frame->frame frame))))))
      (fs
       (frame-val->dir
        (cdr (assoc-equal
              (frame-val->src
               (cdr (assoc-equal (1st-complete (frame->frame frame))
                                 (frame->frame frame))))
              (frame->frame frame))))))
     (:instance
      (:rewrite abs-find-file-of-put-assoc-lemma-6)
      (pathname pathname)
      (frame (frame->frame frame))
      (x (frame-val->src (cdr (assoc-equal (1st-complete (frame->frame frame))
                                           (frame->frame frame)))))))))
  :otf-flg t)

(defthm
  abs-mkdir-correctness-lemma-26
  (implies
   (and (consp (assoc-equal 0 frame))
        (not (consp (frame-val->path (cdr (assoc-equal 0 frame)))))
        (mv-nth 1 (collapse frame))
        (frame-p frame)
        (no-duplicatesp-equal (strip-cars frame))
        (subsetp-equal (abs-addrs (frame->root frame))
                       (frame-addrs-root (frame->frame frame)))
        (abs-separate frame))
   (equal
    (m1-regular-file-p (mv-nth 0 (abs-find-file frame pathname)))
    (m1-regular-file-p (mv-nth 0
                               (hifat-find-file (mv-nth 0 (collapse frame))
                                                pathname)))))
  :hints
  (("goal"
    :in-theory (e/d ((:definition abs-find-file)
                     collapse (:definition collapse-this))
                    ((:rewrite partial-collapse-correctness-lemma-24)
                     (:definition remove-equal)
                     (:definition assoc-equal)
                     (:definition member-equal)
                     (:definition remove-assoc-equal)
                     (:rewrite abs-file-alist-p-correctness-1)
                     (:rewrite nthcdr-when->=-n-len-l)
                     (:rewrite abs-find-file-of-put-assoc-lemma-6)
                     (:rewrite subsetp-when-prefixp)
                     (:definition strip-cars)
                     abs-find-file-helper-of-collapse-3
                     abs-find-file-correctness-1-lemma-3
                     (:rewrite consp-of-nthcdr)
                     (:rewrite abs-find-file-helper-of-collapse-lemma-2)
                     (:rewrite partial-collapse-correctness-lemma-2)
                     (:rewrite put-assoc-equal-without-change . 2)
                     (:rewrite abs-find-file-correctness-lemma-14)
                     (:rewrite prefixp-when-equal-lengths)
                     (:rewrite abs-find-file-correctness-lemma-31)
                     (:definition put-assoc-equal)
                     (:rewrite abs-fs-p-when-hifat-no-dups-p)))
    :induct (collapse frame)
    :expand
    ((:with abs-find-file-of-put-assoc
            (:free (name val frame pathname)
                   (abs-find-file (put-assoc-equal name val frame)
                                  pathname)))
     (:with
      abs-find-file-of-remove-assoc-1
      (abs-find-file (remove-assoc-equal (1st-complete (frame->frame frame))
                                         (frame->frame frame))
                     pathname))))
   ("subgoal *1/6.4'" :expand ((:free (x) (hide x))))))

;; Move later.
(defthm abs-file-p-of-abs-find-file
  (abs-file-p (mv-nth 0 (abs-find-file frame pathname)))
  :hints (("goal" :in-theory (enable abs-find-file))))
(defthmd
  abs-file-p-alt
  (equal (abs-file-p x)
         (or (m1-regular-file-p x)
             (abs-directory-file-p x)))
  :hints (("goal" :do-not-induct t
           :in-theory (enable m1-regular-file-p
                              abs-file-p abs-directory-file-p
                              m1-file->contents m1-file-contents-fix
                              m1-file-p abs-file-contents-p
                              abs-file->contents))))

(defthm
  abs-mkdir-correctness-lemma-27
 (implies
  (and (consp (assoc-equal 0 frame))
       (not (consp (frame-val->path (cdr (assoc-equal 0 frame)))))
       (mv-nth 1 (collapse frame))
       (frame-p frame)
       (no-duplicatesp-equal (strip-cars frame))
       (subsetp-equal (abs-addrs (frame->root frame))
                      (frame-addrs-root (frame->frame frame)))
       (abs-separate frame))
  (equal
   (abs-directory-file-p (mv-nth 0 (abs-find-file frame pathname)))
   (m1-directory-file-p (mv-nth 0
                                (hifat-find-file (mv-nth 0 (collapse frame))
                                                 pathname)))))
 :hints
 (("goal"
   :do-not-induct t
   :in-theory
   (e/d
    (abs-file-p-alt)
    (abs-file-p-of-abs-find-file abs-mkdir-correctness-lemma-26
                                 (:rewrite m1-regular-file-p-correctness-1)
                                 m1-directory-file-p-when-m1-file-p))
   :use
   (abs-file-p-of-abs-find-file
    abs-mkdir-correctness-lemma-26
    (:instance (:rewrite m1-regular-file-p-correctness-1)
               (file (mv-nth 0
                             (hifat-find-file (mv-nth 0 (collapse frame))
                                              pathname))))))
  ("subgoal 1"
   :expand
   (m1-regular-file-p (mv-nth 0
                              (hifat-find-file (mv-nth 0 (collapse frame))
                                               pathname))))))

(defthm
  abs-mkdir-correctness-lemma-28
  (not
   (intersectp-equal
    (names-at
     (frame-val->dir
      (cdr (assoc-equal 0
                        (partial-collapse frame (hifat-dirname pathname)))))
     nil)
    (names-at
     (list
      (find-new-index
       (strip-cars (partial-collapse frame (hifat-dirname pathname)))))
     nil)))
  :hints (("goal" :in-theory (enable names-at abs-fs-fix)
           :do-not-induct t)))

(defthm abs-mkdir-correctness-lemma-29
  (implies (atom n)
           (dist-names (list n) relpath frame))
  :hints (("goal" :in-theory (enable names-at abs-fs-fix dist-names))))

(defthm abs-mkdir-correctness-lemma-30
  (implies (atom n)
           (equal (names-at (list n) relpath) nil))
  :hints (("goal" :in-theory (enable names-at abs-fs-fix))))

(defthm
  abs-mkdir-correctness-lemma-31
  (equal (collapse (frame-with-root (frame->root frame)
                                    (frame->frame frame)))
         (collapse frame))
  :hints
  (("goal"
    :in-theory
    (e/d (collapse collapse-this)
         ((:rewrite partial-collapse-correctness-lemma-24)
          (:definition no-duplicatesp-equal)
          (:definition assoc-equal)
          (:definition member-equal)
          (:rewrite subsetp-when-prefixp)
          (:rewrite prefixp-when-equal-lengths)
          (:definition remove-equal)
          (:rewrite strip-cars-of-remove-assoc)
          (:rewrite assoc-after-put-assoc)
          (:rewrite strip-cars-of-put-assoc)
          (:rewrite no-duplicatesp-of-strip-cars-of-frame->frame)
          (:definition remove-assoc-equal)
          (:rewrite remove-when-absent)
          (:rewrite remove-assoc-of-put-assoc)
          (:rewrite remove-assoc-of-remove-assoc)
          (:linear count-free-clusters-correctness-1)
          abs-separate-of-frame->frame-of-collapse-this-lemma-8))
    :do-not-induct t
    :expand ((collapse frame)
             (collapse (frame-with-root (frame->root frame)
                                        (frame->frame frame))))))
  :rule-classes
  (:rewrite
   (:rewrite
    :corollary
    (collapse-equiv (frame-with-root (frame->root frame)
                                     (frame->frame frame))
                    frame)
    :hints (("Goal" :in-theory (enable collapse-equiv))))))

;; (thm (implies
;;       (and (collapse-equiv frame1 frame2)
;;            (consp (assoc-equal 0 frame1))
;;            (not (consp (frame-val->path (cdr (assoc-equal 0 frame1)))))
;;            (mv-nth 1 (collapse frame1))
;;            (frame-p frame1)
;;            (no-duplicatesp-equal (strip-cars frame1))
;;            (subsetp-equal (abs-addrs (frame->root frame1))
;;                           (frame-addrs-root (frame->frame frame1)))
;;            (abs-separate frame1)
;;            (or
;;             (m1-regular-file-p (mv-nth 0 (abs-find-file frame1 pathname)))
;;             (abs-complete
;;              (abs-file->contents (mv-nth 0 (abs-find-file frame1 pathname)))))
;;            (consp (assoc-equal 0 frame2))
;;            (not (consp (frame-val->path (cdr (assoc-equal 0 frame2)))))
;;            (mv-nth 1 (collapse frame2))
;;            (frame-p frame2)
;;            (no-duplicatesp-equal (strip-cars frame2))
;;            (subsetp-equal (abs-addrs (frame->root frame2))
;;                           (frame-addrs-root (frame->frame frame2)))
;;            (abs-separate frame2)
;;            (or
;;             (m1-regular-file-p (mv-nth 0 (abs-find-file frame2 pathname)))
;;             (abs-complete
;;              (abs-file->contents (mv-nth 0 (abs-find-file frame2 pathname))))))
;;       (equal (abs-find-file frame1 pathname)
;;              (abs-find-file frame2 pathname)))
;;      :hints
;;      (("goal"
;;        :do-not-induct t
;;        :in-theory (e/d
;;                    (collapse-equiv)
;;                    (abs-find-file-correctness-2
;;                     abs-mkdir-correctness-lemma-26))
;;        :use ((:instance
;;               abs-find-file-correctness-2 (frame frame1))
;;              (:instance
;;               abs-find-file-correctness-2 (frame frame2)))))
;;      :otf-flg t)

(defthm
  abs-mkdir-correctness-lemma-32
  (implies (and (mv-nth 1 (collapse frame))
                (atom pathname))
           (equal (partial-collapse frame pathname)
                  (if (atom (frame->frame frame))
                      frame
                      (frame-with-root (mv-nth 0 (collapse frame))
                                       nil))))
  :hints
  (("goal"
    :in-theory (e/d (partial-collapse collapse)
                    ((:definition no-duplicatesp-equal)
                     (:rewrite partial-collapse-correctness-lemma-24)
                     (:definition assoc-equal)
                     (:rewrite subsetp-when-prefixp)
                     (:definition member-equal)
                     (:definition true-listp)
                     (:rewrite put-assoc-equal-without-change . 2)
                     abs-separate-of-frame->frame-of-collapse-this-lemma-8
                     (:rewrite true-list-fix-when-true-listp)
                     (:rewrite true-listp-when-string-list)
                     (:definition string-listp)
                     (:definition put-assoc-equal)
                     (:rewrite remove-assoc-of-put-assoc)
                     (:rewrite abs-fs-p-when-hifat-no-dups-p)
                     (:definition remove-assoc-equal)
                     (:definition remove-equal)
                     (:rewrite fat32-filename-p-correctness-1)))
    :induct (collapse frame)
    :expand ((partial-collapse frame pathname)
             (collapse-this frame
                            (1st-complete (frame->frame frame)))))))

(defthm
  abs-mkdir-correctness-lemma-33
  (implies (natp n)
           (ctx-app-ok (list n) n nil))
  :hints (("goal" :in-theory (enable ctx-app-ok addrs-at abs-fs-fix)
           :do-not-induct t)))

(defthmd abs-mkdir-correctness-lemma-34
  (implies (and (not (null x))
                (atom (remove-assoc-equal x alist))
                (no-duplicatesp-equal (strip-cars alist)))
           (list-equiv alist
                       (if (atom (assoc-equal x alist))
                           nil (list (assoc-equal x alist))))))

(defthmd
  abs-mkdir-correctness-lemma-35
  (implies (and (atom (frame->frame frame))
                (no-duplicatesp-equal (strip-cars frame))
                (consp (assoc-equal 0 frame))
                (equal (frame-val->src (cdr (assoc-equal 0 frame)))
                       0)
                (not (consp (frame-val->path (cdr (assoc-equal 0 frame)))))
                (frame-p frame))
           (equal (list (cons 0
                              (make-frame-val :dir (frame->root frame)
                                              :src 0
                                              :path nil)))
                  frame))
  :hints (("goal" :in-theory (enable frame->frame frame->root frame-p)
           :do-not-induct t
           :use (:instance abs-mkdir-correctness-lemma-34 (x 0)
                           (alist frame))
           :expand (assoc-equal 0 frame))))

(defthm
  abs-mkdir-correctness-lemma-36
  (implies
   (and (member-equal new-index y)
        (subsetp-equal (abs-addrs fs) y)
        (abs-file-alist-p fs)
        (abs-no-dups-p fs)
        (natp new-index))
   (subsetp-equal (abs-addrs (mv-nth 1 (abs-disassoc fs pathname new-index)))
                  y))
  :hints (("goal" :in-theory (enable abs-disassoc)
           :expand (abs-addrs (list new-index)))))

(defthm abs-mkdir-correctness-lemma-37
  (implies (not (consp (frame->frame frame)))
           (dist-names (frame->root frame)
                       nil (remove-assoc-equal 0 frame)))
  :hints (("goal" :in-theory (enable frame->frame))))

(defthm abs-mkdir-correctness-lemma-38
  (implies (atom pathname)
           (equal (abs-find-file-helper fs pathname)
                  (mv (abs-file-fix nil) *enoent*)))
  :hints (("goal" :in-theory (enable abs-find-file-helper))))

(defthm abs-mkdir-correctness-lemma-39
  (implies (atom pathname)
           (equal (abs-find-file frame pathname)
                  (mv (abs-file-fix nil) *enoent*)))
  :hints (("goal" :in-theory (enable abs-find-file))))

(defthm
  abs-mkdir-correctness-lemma-40
  (implies
   (and (no-duplicatesp-equal (strip-cars frame))
        (frame-p frame)
        (not (consp (frame-val->path (cdr (assoc-equal 0 frame)))))
        (abs-separate frame)
        (subsetp-equal (abs-addrs (frame->root frame))
                       (frame-addrs-root (frame->frame frame))))
   (subsetp-equal
    (abs-addrs
     (frame-val->dir$inline
      (cdr (assoc-equal 0
                        (partial-collapse frame (hifat-dirname pathname))))))
    (frame-addrs-root
     (frame->frame (partial-collapse frame (hifat-dirname pathname))))))
  :hints
  (("goal"
    :do-not-induct t
    :cases
    ((not
      (equal
       (frame-val->dir
        (cdr (assoc-equal 0
                          (partial-collapse frame (hifat-dirname pathname)))))
       (frame->root (partial-collapse frame (hifat-dirname pathname)))))))
   ("subgoal 1" :in-theory (enable frame->root))))

(defthm
  names-at-of-abs-disassoc-2
  (implies (abs-fs-p fs)
           (equal (names-at (mv-nth 0 (abs-disassoc fs pathname new-index))
                            relpath)
                  (if (equal (mv-nth 1 (abs-disassoc fs pathname new-index))
                             fs)
                      nil
                      (names-at fs (append pathname relpath)))))
  :hints
  (("goal" :in-theory
    (e/d (abs-top-addrs names-at
                        abs-disassoc fat32-filename-list-fix
                        abs-fs-p abs-file-alist-p abs-no-dups-p)
         ((:rewrite abs-fs-p-correctness-1)
          (:rewrite abs-no-dups-p-of-put-assoc-equal)
          (:rewrite abs-fs-fix-of-put-assoc-equal-lemma-1)
          (:rewrite abs-fs-p-when-hifat-no-dups-p)
          (:rewrite hifat-find-file-correctness-1-lemma-1)
          (:rewrite consp-of-assoc-of-abs-fs-fix)
          (:rewrite abs-file->contents-when-m1-file-p)
          (:rewrite subsetp-when-prefixp)
          (:rewrite remove-when-absent)
          (:rewrite absfat-equiv-implies-set-equiv-addrs-at-1-lemma-1)
          (:definition remove-equal)
          (:rewrite m1-file-alist-p-of-cdr-when-m1-file-alist-p)
          (:definition member-equal)
          (:rewrite abs-file-alist-p-when-m1-file-alist-p)
          (:rewrite abs-file-alist-p-correctness-1)
          (:rewrite abs-no-dups-p-when-m1-file-alist-p)
          (:rewrite abs-addrs-when-m1-file-alist-p-lemma-2)
          (:rewrite abs-addrs-when-m1-file-alist-p)
          (:rewrite member-of-abs-addrs-when-natp . 2)
          (:rewrite member-of-abs-fs-fix-when-natp)
          (:rewrite abs-file-contents-p-when-m1-file-contents-p)
          (:rewrite fat32-filename-fix-when-fat32-filename-p))))))

;; I regard both of the following rewrite rules as dangerous, so I'm keeping
;; them disabled except for where they're needed.
(defthmd frame->frame-of-put-assoc
  (equal (frame->frame (put-assoc-equal key val frame))
         (if (equal 0 key)
             (frame->frame frame)
             (put-assoc-equal key val (frame->frame frame))))
  :hints (("goal" :in-theory (enable frame->frame))))
(defthm frame->root-of-put-assoc
  (equal (frame->root (put-assoc-equal key val frame))
         (if (equal 0 key)
             (frame-val->dir val)
             (frame->root frame)))
  :hints (("goal" :in-theory (enable frame->root))))

(thm
 (implies
  (and
   (no-duplicatesp-equal (strip-cars frame))
   (frame-p frame)
   (equal (frame-val->src$inline (cdr (assoc-equal 0 frame))) '0)
   ;; i know, these both mean the same thing!
   (not (consp (frame-val->path$inline (cdr (assoc-equal 0 frame)))))
   (equal
    (len
     (frame-val->path
      (cdr (assoc-equal 0
                        (partial-collapse frame (hifat-dirname pathname))))))
    0)
   (frame-reps-fs frame fs)
   (consp (assoc-equal 0 frame))
   (not
    (consp
     (abs-addrs
      (remove-assoc-equal
       (hifat-basename pathname)
       (mv-nth
        0
        (abs-disassoc
         (frame-val->dir$inline
          (cdr
           (assoc-equal (abs-find-file-src
                         (partial-collapse frame (hifat-dirname pathname))
                         (hifat-dirname pathname))
                        (partial-collapse frame (hifat-dirname pathname)))))
         (nthcdr
          (len
           (frame-val->path$inline
            (cdr (assoc-equal
                  (abs-find-file-src
                   (partial-collapse frame (hifat-dirname pathname))
                   (hifat-dirname pathname))
                  (partial-collapse frame (hifat-dirname pathname))))))
          (hifat-dirname pathname))
         (find-new-index
          (strip-cars (partial-collapse frame (hifat-dirname pathname))))))))))
   (NOT
    (CONSP
     (ABS-ADDRS
      (ABS-FILE->CONTENTS$INLINE
       (MV-NTH 0
               (ABS-FIND-FILE (PARTIAL-COLLAPSE FRAME (HIFAT-DIRNAME PATHNAME))
                              (HIFAT-DIRNAME PATHNAME)))))))
   (not
    (member-equal
     (find-new-index
      (strip-cars (partial-collapse frame (hifat-dirname pathname))))
     (abs-addrs
      (frame-val->dir$inline
       (cdr
        (assoc-equal
         (abs-find-file-src (partial-collapse frame (hifat-dirname pathname))
                            (hifat-dirname pathname))
         (partial-collapse frame (hifat-dirname pathname))))))))
   ;; This hypothesis is causing a lot of trouble...
   ;; (equal
   ;;  (frame-with-root (frame->root frame) (frame->frame frame))
   ;;  frame)
   )
  (and
   (frame-reps-fs
    (mv-nth 0 (abs-mkdir frame pathname))
    (mv-nth 0 (hifat-mkdir (mv-nth 0 (collapse frame)) pathname)))
   (equal
    (mv-nth 2 (abs-mkdir frame pathname))
    (mv-nth 2 (hifat-mkdir (mv-nth 0 (collapse frame)) pathname)))))
 :hints (("goal" :in-theory
          (e/d (abs-mkdir hifat-mkdir collapse 1st-complete
                          collapse-this hifat-place-file
                          hifat-find-file abs-find-file
                          abs-find-file-src
                          abs-disassoc
                          abs-mkdir-correctness-lemma-16
                          abs-mkdir-correctness-lemma-3
                          abs-separate dist-names abs-fs-fix
                          abs-addrs frame-addrs-root
                          ctx-app)
               ((:REWRITE PUT-ASSOC-EQUAL-WITHOUT-CHANGE . 2)
                (:REWRITE
                                ABS-SEPARATE-OF-FRAME->FRAME-OF-COLLAPSE-THIS-LEMMA-8
                                . 2)
                (:DEFINITION MEMBER-EQUAL)
                (:REWRITE ABS-ADDRS-OF-CTX-APP-2)
                (:REWRITE REMOVE-WHEN-ABSENT)
                (:REWRITE ABS-MKDIR-CORRECTNESS-LEMMA-26)
                (:REWRITE
                 ABS-SEPARATE-OF-FRAME->FRAME-OF-COLLAPSE-THIS-LEMMA-10)
                (:REWRITE ABS-FILE->CONTENTS-WHEN-M1-FILE-P)
                (:REWRITE
                 ABS-FS-FIX-OF-PUT-ASSOC-EQUAL-LEMMA-1)
                (:LINEAR COUNT-FREE-CLUSTERS-CORRECTNESS-1)
                (:REWRITE
                 PARTIAL-COLLAPSE-CORRECTNESS-LEMMA-24)
                (:DEFINITION PUT-ASSOC-EQUAL)
                (:REWRITE M1-FILE-P-WHEN-M1-REGULAR-FILE-P)
                (:DEFINITION LEN)
                (:REWRITE ABS-DIRECTORY-FILE-P-WHEN-M1-FILE-P)
                (:REWRITE
                 ABS-ADDRS-WHEN-M1-FILE-ALIST-P-LEMMA-2)
                (:REWRITE NTHCDR-WHEN->=-N-LEN-L)
                (:REWRITE ABS-FILE-FIX-WHEN-ABS-FILE-P)
                (:REWRITE
                 CTX-APP-OK-WHEN-ABSFAT-EQUIV-LEMMA-4)
                (:REWRITE ABS-FIND-FILE-CORRECTNESS-LEMMA-2)
                (:LINEAR LEN-OF-SEQ-THIS-1)
                (:REWRITE ASSOC-AFTER-REMOVE-ASSOC)
                (:REWRITE ABS-MKDIR-CORRECTNESS-LEMMA-14)
                (:DEFINITION ACL2-NUMBER-LISTP)
                (:REWRITE 1ST-COMPLETE-CORRECTNESS-1)
                (:REWRITE ABS-ADDRS-WHEN-M1-FILE-CONTENTS-P)
                (:REWRITE
                 ABS-SEPARATE-OF-FRAME->FRAME-OF-COLLAPSE-THIS-LEMMA-11)
                (:REWRITE ABS-FIND-FILE-CORRECTNESS-1-LEMMA-3)
                (:REWRITE
                 ABSFAT-EQUIV-IMPLIES-SET-EQUIV-ADDRS-AT-1-LEMMA-1)
                (:REWRITE
                 ABS-FS-FIX-OF-PUT-ASSOC-EQUAL-LEMMA-2)
                (:REWRITE FINAL-VAL-OF-COLLAPSE-THIS-LEMMA-3)
                (:DEFINITION INTEGER-LISTP)
                (:REWRITE ABS-FS-P-OF-CTX-APP)
                (:TYPE-PRESCRIPTION
                 ABS-FS-FIX-OF-PUT-ASSOC-EQUAL-LEMMA-3)
                (:REWRITE M1-FILE-CONTENTS-P-CORRECTNESS-1)
                (:DEFINITION BINARY-APPEND)
                (:DEFINITION TRUE-LISTP)
                (:REWRITE
                 PARTIAL-COLLAPSE-CORRECTNESS-LEMMA-2)
                (:DEFINITION RATIONAL-LISTP)
                (:REWRITE CONSP-OF-NTHCDR)
                (:REWRITE LIST-EQUIV-WHEN-TRUE-LISTP)))
          :do-not-induct t))
 :otf-flg t)

(in-package "ACL2")

(include-book "test-stuff")

(defun
  rm-list-extra-hypothesis
  (fat32-in-memory name-list)
  (declare (xargs :stobjs fat32-in-memory
                  :guard (and (lofat-fs-p fat32-in-memory)
                              (string-listp name-list))
                  :measure (len name-list)))
  (b*
      (((when (atom name-list))
        (mv fat32-in-memory t))
       (fat32-pathname (pathname-to-fat32-pathname
                        (coerce (car name-list) 'list)))
       ((unless (fat32-filename-list-p fat32-pathname))
        (mv fat32-in-memory nil))
       ((mv fs error-code)
        (lofat-to-hifat fat32-in-memory))
       ((unless (equal error-code 0))
        (mv fat32-in-memory nil))
       ((mv fs & error-code)
        (hifat-unlink fs fat32-pathname))
       ((unless (and (equal error-code 0)
                     (m1-bounded-file-alist-p fs)
                     (<= (hifat-entry-count fs)
                         (max-entry-count fat32-in-memory))))
        (mv fat32-in-memory nil))
       ((mv fat32-in-memory error-code)
        (hifat-to-lofat fat32-in-memory fs))
       ((unless (equal error-code 0))
        (mv fat32-in-memory nil)))
    (rm-list-extra-hypothesis fat32-in-memory (cdr name-list))))

(defthm rm-list-correctness-1-lemma-1
  (equal (mv-nth 1 (rm-list fat32-in-memory pathname-list 1))
         1))

(defthm
  rm-list-correctness-1-lemma-2
  (implies
   (and
    (lofat-fs-p fat32-in-memory)
    (equal (mv-nth 1
                   (find-file-by-pathname
                    (mv-nth 0
                            (lofat-to-hifat fat32-in-memory))
                    fat32-pathname))
           *enoent*)
    ;; storing some hypotheses here
    (not (null (mv-nth 1
                       (rm-list-extra-hypothesis
                        fat32-in-memory pathname-list)))))
   (equal
    (mv-nth 1
            (find-file-by-pathname
             (mv-nth 0
                     (lofat-to-hifat
                      (mv-nth 0
                              (rm-list
                               fat32-in-memory
                               pathname-list
                               exit-status))))
             fat32-pathname))
    *enoent*))
  :hints (("goal" :in-theory (e/d (lofat-unlink)
                                  (find-file-by-pathname
                                   (:DEFINITION PATHNAME-TO-FAT32-PATHNAME)
                                   (:DEFINITION NAME-TO-FAT32-NAME)))
           :induct
           (rm-list
            fat32-in-memory
            pathname-list
            exit-status))))

(defthmd
  rm-list-correctness-1-lemma-3
  (implies
   (and (lofat-fs-p fat32-in-memory)
        (member-equal pathname pathname-list)
        (equal (mv-nth 1
                       (rm-list fat32-in-memory pathname-list exit-status))
               0)
        (not (null (mv-nth 1
                           (rm-list-extra-hypothesis
                            fat32-in-memory pathname-list)))))
   (equal
    (mv-nth
     1
     (find-file-by-pathname
      (mv-nth 0
              (lofat-to-hifat
               (mv-nth 0
                       (rm-list fat32-in-memory pathname-list exit-status))))
      (pathname-to-fat32-pathname (explode pathname))))
    *enoent*))
  :hints
  (("goal"
    :in-theory (e/d
                (lofat-unlink)
                ((:definition pathname-to-fat32-pathname)
                 (:definition name-to-fat32-name)
                 (:rewrite take-of-take-split)
                 (:linear len-of-member-equal))))))

(defthm
  rm-list-correctness-1
  (implies
   (and (lofat-fs-p fat32-in-memory)
        (member-equal pathname pathname-list)
        (equal (mv-nth 1
                       (rm-list fat32-in-memory pathname-list exit-status))
               0)
        (not (null (mv-nth 1
                           (rm-list-extra-hypothesis
                            fat32-in-memory pathname-list))))
        (equal (mv-nth '1
                       (lofat-to-hifat (mv-nth '0
                                               (rm-list fat32-in-memory
                                                        pathname-list exit-status))))
               '0))
   (not
    (equal
     (mv-nth
      1
      (lofat-lstat
       (mv-nth 0
               (rm-list fat32-in-memory pathname-list exit-status))
       (pathname-to-fat32-pathname (explode pathname))))
     0)))
  :hints
  (("goal" :do-not-induct t
    :in-theory (e/d
                (lofat-unlink)
                ((:definition pathname-to-fat32-pathname)
                 (:definition name-to-fat32-name)
                 (:rewrite take-of-take-split)
                 (:linear len-of-member-equal)))
    :use
    rm-list-correctness-1-lemma-3)))

(defthm ls-list-correctness-1-lemma-1
  (implies (not
            (equal
             (mv-nth
              1
              (ls-list fat32-in-memory name-list exit-status))
             exit-status))
           (equal
            (mv-nth
             1
             (ls-list fat32-in-memory name-list exit-status))
            2))
  :rule-classes :linear)

;; Not currently used.
(defthmd ls-list-correctness-1-lemma-2
  (implies
   (not (equal (mv-nth 1
                       (lofat-lstat fat32-in-memory pathname))
               0))
   (equal (mv-nth 1
                  (lofat-lstat fat32-in-memory pathname))
          -1))
  :hints (("goal" :in-theory (enable lofat-lstat))))

(defthm
  ls-list-correctness-1
  (implies
   (and
    (member-equal pathname name-list)
    (not
     (equal
      (mv-nth 1
              (ls-list fat32-in-memory name-list exit-status))
      2)))
   (and
    (fat32-filename-list-p
     (pathname-to-fat32-pathname (explode pathname)))
    (equal
     (mv-nth
      1
      (lofat-lstat
       fat32-in-memory
       (pathname-to-fat32-pathname (explode pathname))))
     0))))

(defthm
  lstat-after-unlink-1
  (implies
   (and
    (lofat-fs-p fat32-in-memory)
    (m1-bounded-file-alist-p
     (mv-nth
      '0
      (remove-file-by-pathname (mv-nth '0
                                       (lofat-to-hifat fat32-in-memory))
                               pathname)))
    (not
     (<
      (max-entry-count fat32-in-memory)
      (hifat-entry-count
       (mv-nth
        '0
        (remove-file-by-pathname (mv-nth '0
                                         (lofat-to-hifat fat32-in-memory))
                                 pathname)))))
    (equal
     (mv-nth
      '1
      (hifat-to-lofat
       fat32-in-memory
       (mv-nth
        '0
        (remove-file-by-pathname (mv-nth '0
                                         (lofat-to-hifat fat32-in-memory))
                                 pathname))))
     0))
   (b* (((mv fat32-in-memory unlink-errno)
         (lofat-unlink fat32-in-memory pathname))
        ((mv & lstat-errno)
         (lofat-lstat fat32-in-memory pathname)))
     (implies (equal unlink-errno 0)
              (equal lstat-errno -1))))
  :hints (("goal"
           :in-theory (enable lofat-unlink))))

(defthm
  ls-1-after-rm-1
  (implies
   (and
    (lofat-fs-p fat32-in-memory)
    (< 0
       (len (intersection-equal ls-pathnames rm-pathnames)))
    (not
     (null
      (mv-nth
       1
       (rm-list-extra-hypothesis
        (mv-nth
         0
         (string-to-lofat fat32-in-memory disk-image-string))
        rm-pathnames))))
    (equal
     (mv-nth
      '1
      (lofat-to-hifat
       (mv-nth
        '0
        (rm-list
         (mv-nth
          '0
          (string-to-lofat fat32-in-memory disk-image-string))
         rm-pathnames '0))))
     '0))
   (b* (((mv fat32-in-memory
             disk-image-string rm-exit-status)
         (rm-1 fat32-in-memory
               disk-image-string rm-pathnames))
        ((mv & & ls-exit-status)
         (ls-1 fat32-in-memory
               ls-pathnames disk-image-string)))
     (implies (equal rm-exit-status 0)
              (equal ls-exit-status 2))))
  :hints
  (("goal"
    :do-not-induct t
    :in-theory (e/d (rm-1 ls-1)
                    ((:rewrite rm-list-correctness-1)
                     ls-list-correctness-1 nth
                     (:definition pathname-to-fat32-pathname)
                     (:definition name-to-fat32-name)
                     (:definition rm-list)
                     (:definition find-file-by-pathname)))
    :use
    ((:instance
      (:rewrite rm-list-correctness-1)
      (pathname
       (nth 0
            (intersection-equal ls-pathnames rm-pathnames)))
      (exit-status 0)
      (pathname-list rm-pathnames)
      (fat32-in-memory
       (mv-nth
        0
        (string-to-lofat fat32-in-memory disk-image-string))))
     (:instance
      (:rewrite ls-list-correctness-1)
      (exit-status 0)
      (pathname
       (nth 0
            (intersection-equal ls-pathnames rm-pathnames)))
      (name-list ls-pathnames)
      (fat32-in-memory
       (mv-nth
        0
        (rm-list
         (mv-nth
          0
          (string-to-lofat fat32-in-memory disk-image-string))
         rm-pathnames 0))))))))

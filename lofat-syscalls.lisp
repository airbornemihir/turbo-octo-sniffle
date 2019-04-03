(in-package "ACL2")

;  lofat-syscalls.lisp                                 Mihir Mehta

; Syscalls for LoFAT. These syscalls usually return, among other things, a
; return value (corresponding to the C return value) and an errno.

(include-book "lofat")
(include-book "hifat-syscalls")

;; This needs some revision... obviously, we don't want to be staring into the
;; computation to get the root directory's directory entries here.
(defun lofat-open (pathname fat32-in-memory fd-table file-table)
  (declare (xargs :guard (and (lofat-fs-p fat32-in-memory)
                              (fat32-filename-list-p pathname)
                              (fd-table-p fd-table)
                              (file-table-p file-table))
                  :stobjs fat32-in-memory))
  (b*
      ((fd-table (fd-table-fix fd-table))
       (file-table (file-table-fix file-table))
       ((mv root-contents &)
        (get-clusterchain-contents
         fat32-in-memory
         (fat32-entry-mask (bpb_rootclus fat32-in-memory))
         2097152))
       ((mv & errno)
        (lofat-find-file-by-pathname
         fat32-in-memory
         (make-dir-ent-list
          (string=>nats
           root-contents))
         pathname))
       ((unless (equal errno 0))
        (mv fd-table file-table -1 errno))
       (file-table-index
        (find-new-index (strip-cars file-table)))
       (fd-table-index
        (find-new-index (strip-cars fd-table))))
    (mv
     (cons
      (cons fd-table-index file-table-index)
      fd-table)
     (cons
      (cons file-table-index (make-file-table-element :pos 0 :fid pathname))
      file-table)
     fd-table-index 0)))

(defthm
  lofat-open-refinement
  (implies
   (equal (mv-nth 3 (lofat-to-hifat fat32-in-memory))
          0)
   (equal
    (lofat-open pathname
                fat32-in-memory fd-table file-table)
    (hifat-open pathname
                (mv-nth 0 (lofat-to-hifat fat32-in-memory))
                fd-table file-table)))
  :hints (("goal" :in-theory (enable lofat-to-hifat))))

;; This needs some revision... obviously, we don't want to be staring into the
;; computation to get the root directory's directory entries here.
(defun
  lofat-pread
  (fd count offset fat32-in-memory fd-table file-table)
  (declare (xargs :guard (and (natp fd)
                              (natp count)
                              (natp offset)
                              (fd-table-p fd-table)
                              (file-table-p file-table)
                              (lofat-fs-p fat32-in-memory))
                  :stobjs fat32-in-memory))
  (b*
      ((fd-table-entry (assoc-equal fd fd-table))
       ((unless (consp fd-table-entry))
        (mv "" -1 *ebadf*))
       (file-table-entry (assoc-equal (cdr fd-table-entry)
                                      file-table))
       ((unless (consp file-table-entry))
        (mv "" -1 *ebadf*))
       (pathname (file-table-element->fid (cdr file-table-entry)))
       ((mv root-contents &)
        (get-clusterchain-contents
         fat32-in-memory
         (fat32-entry-mask (bpb_rootclus fat32-in-memory))
         2097152))
       ((mv file error-code)
        (lofat-find-file-by-pathname
         fat32-in-memory
         (make-dir-ent-list
          (string=>nats
           root-contents))
         pathname))
       ((unless (and (equal error-code 0)
                     (lofat-regular-file-p file)))
        (mv "" -1 error-code))
       (file-contents (lofat-file->contents file))
       (new-offset (min (+ offset count)
                        (length file-contents)))
       (buf (subseq file-contents
                    (min offset
                         (length file-contents))
                    new-offset)))
    (mv buf (length buf) 0)))

(defthm
  lofat-pread-refinement
  (implies (equal (mv-nth 3 (lofat-to-hifat fat32-in-memory))
                  0)
           (equal (lofat-pread fd count offset
                               fat32-in-memory fd-table file-table)
                  (hifat-pread fd count offset
                               (mv-nth 3 (lofat-to-hifat fat32-in-memory))
                               fd-table file-table)))
  :hints (("goal" :in-theory (enable lofat-to-hifat))))

(defun lofat-lstat (fat32-in-memory pathname)
  (declare (xargs :guard (and (lofat-fs-p fat32-in-memory)
                              (fat32-filename-list-p pathname))
                  :stobjs fat32-in-memory))
  (b*
      (((mv root-contents &)
        (get-clusterchain-contents
         fat32-in-memory
         (fat32-entry-mask (bpb_rootclus fat32-in-memory))
         2097152))
       ((mv file errno)
        (lofat-find-file-by-pathname
         fat32-in-memory
         (make-dir-ent-list
          (string=>nats
           root-contents))
         pathname))
       ((when (not (equal errno 0)))
        (mv (make-struct-stat) -1 errno)))
    (mv
       (make-struct-stat
        :st_size (dir-ent-file-size
                  (lofat-file->dir-ent file)))
       0 0)))

(defthm lofat-lstat-refinement
  (implies
   (equal (mv-nth 3 (lofat-to-hifat fat32-in-memory))
          0)
   (equal
    (lofat-lstat fat32-in-memory pathname)
    (hifat-lstat (mv-nth 0 (lofat-to-hifat fat32-in-memory))
                 pathname)))
  :hints (("goal" :in-theory (enable lofat-to-hifat))))

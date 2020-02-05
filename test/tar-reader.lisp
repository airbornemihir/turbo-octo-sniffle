(include-book "../tar-stuff")

(b*
    (((mv & disk-image-location state)
      (getenv$ "DISK" state))
     ((mv fat32-in-memory &)
      (disk-image-to-lofat
       fat32-in-memory disk-image-location state))
     ((mv & val state)
      (getenv$ "TAR_INPUT" state))
     (input-pathname (pathname-to-fat32-pathname (coerce val 'list)))
     ((mv & val state)
      (getenv$ "TAR_OUTPUT" state))
     (output-pathname (pathname-to-fat32-pathname (coerce val 'list)))
     ((mv val error-code &)
      (lofat-lstat fat32-in-memory input-pathname))
     ((unless (and (fat32-filename-list-p output-pathname)
                   (equal error-code 0)))
      (mv fat32-in-memory state))
     (file-length (struct-stat->st_size val))
     ((mv fd-table file-table fd &)
      (lofat-open input-pathname nil nil))
     ((mv file-text file-read-length &)
      (lofat-pread
       fd file-length 0 fat32-in-memory fd-table file-table))
     ((unless (equal file-read-length file-length))
      (mv fat32-in-memory state))
     ((mv state fat32-in-memory fd-table file-table)
      (process-block-sequence file-text state fat32-in-memory fd-table
                              file-table output-pathname))
     ((mv channel state) (open-output-channel :string :object state))
     (state (print-object$-ser fd-table nil channel state))
     (state (print-object$-ser file-table nil channel state))
     ((mv & str2 state) (get-output-stream-string$ channel state))
     (state (princ$ "fd-table and file-table, respectively, are" *standard-co* state))
     (state (newline *standard-co* state))
     (state (princ$ str2 *standard-co* state))
     ((mv state &)
      (lofat-to-disk-image
       fat32-in-memory disk-image-location state)))
  (mv fat32-in-memory state))
(include-book "std/util/bstar" :dir :system)

(defconst *cluster-size* 1024)

(defconst *count-of-clusters* 70000)

(defconst *default-string* (coerce
                            (make-list *cluster-size* :initial-element #\0)
                            'string))

(make-event
 `(defstobj text-store

    (string-array :type (array string (*count-of-clusters*))
         :resizable t
         ;; per spec
         :initially ,*default-string*)

    (byte-array :type (array (unsigned-byte 8) (,(* *count-of-clusters* *cluster-size*)))
         :resizable t
         ;; per spec
         :initially 0)

    (character-array :type (array character (,(* *count-of-clusters* *cluster-size*)))
         :resizable t
         ;; per spec
         :initially #\0)))

(defthm
  byte-array-to-character-list-helper-guard-lemma-1
  (implies (byte-arrayp l)
           (iff (unsigned-byte-p 8 (nth n l))
                (< (nfix n) (len l))))
  :rule-classes
  ((:rewrite :corollary (implies (and (byte-arrayp l)
                                      (< (nfix n) (len l)))
                                 (integerp (nth n l))))
   (:linear :corollary (implies (and (byte-arrayp l)
                                     (< (nfix n) (len l)))
                                (and (<= 0 (nth n l))
                                     (< (nth n l) 256))))))

(defun
  byte-array-to-character-list-helper
  (text-store len ac)
  (declare
   (xargs :stobjs text-store
          :guard (and (text-storep text-store)
                      (natp len)
                      (<= len (byte-array-length text-store)))))
  (if (zp len)
      ac
      (byte-array-to-character-list-helper
       text-store (- len 1)
       (cons (code-char (byte-arrayi (- len 1) text-store))
             ac))))

(thm (equal (character-listp (byte-array-to-character-list-helper
                              text-store len ac))
            (character-listp ac)))

(b*
    ((character-list
      (time$
       (byte-array-to-character-list-helper
        text-store (byte-array-length text-store) nil)))
     (string
      (time$ (coerce character-list 'string)))
     ((mv channel state)
      (open-output-channel "test.txt" :character state))
     (state
      (time$ (princ$ string channel state)))
     (state
      (close-output-channel channel state)))
  state)

(defthm
  character-array-to-character-list-helper-guard-lemma-1
  (implies (character-arrayp l)
           (iff (characterp (nth n l))
                (< (nfix n) (len l))))
  :rule-classes
  ((:rewrite :corollary (implies (character-arrayp l)
                                 (equal (characterp (nth n l))
                                        (< (nfix n) (len l))))
             :hints (("goal" :do-not-induct t)))))

(defun
  character-array-to-character-list-helper
  (text-store len ac)
  (declare
   (xargs
    :stobjs text-store
    :guard (and (text-storep text-store)
                (natp len)
                (<= len
                    (character-array-length text-store)))))
  (if (zp len)
      ac
      (character-array-to-character-list-helper
       text-store (- len 1)
       (cons (character-arrayi (- len 1) text-store)
             ac))))

(thm (implies
      (and (text-storep text-store) (<= len (character-array-length text-store)))
      (equal (character-listp (character-array-to-character-list-helper
                               text-store len ac))
             (character-listp ac))))

(b*
    ((character-list
      (time$
       (character-array-to-character-list-helper
        text-store (character-array-length text-store) nil)))
     (string
      (time$ (coerce character-list 'string)))
     ((mv channel state)
      (open-output-channel "test.txt" :character state))
     (state
      (time$ (princ$ string channel state)))
     (state
      (close-output-channel channel state)))
  state)

(defthm
  string-array-to-character-list-helper-guard-lemma-1
  (implies (string-arrayp l)
           (iff (stringp (nth n l))
                (< (nfix n) (len l))))
  :rule-classes
  ((:rewrite :corollary (implies (string-arrayp l)
                                 (equal (stringp (nth n l))
                                        (< (nfix n) (len l))))
             :hints (("goal" :do-not-induct t)))))

(defun
  string-array-to-character-list-helper
  (text-store len ac)
  (declare
   (xargs
    :stobjs text-store
    :guard (and (text-storep text-store)
                (natp len)
                (<= len (string-array-length text-store)))))
  (if (zp len)
      ac
      (string-array-to-character-list-helper
       text-store (- len 1)
       (append (coerce (string-arrayi (- len 1) text-store)
                       'list)
               ac))))

(thm (implies
      (and (text-storep text-store) (<= len (string-array-length text-store)))
      (equal (character-listp (string-array-to-character-list-helper
                               text-store len ac))
             (character-listp ac))))

(b*
    ((character-list
      (time$
       (string-array-to-character-list-helper
        text-store (string-array-length text-store) nil)))
     (string
      (time$ (coerce character-list 'string)))
     ((mv channel state)
      (open-output-channel "test.txt" :character state))
     (state
      (time$ (princ$ string channel state)))
     (state
      (close-output-channel channel state)))
  state)

(defun
  string-array-to-output-channel-helper
  (text-store len channel state)
  (declare
   (xargs
    :stobjs (text-store state)
    :guard (and (text-storep text-store)
                (natp len)
                (<= len (string-array-length text-store))
                (symbolp channel)
                (open-output-channel-p channel
                                       :character state))))
  (b*
      (((when (zp len)) state)
       (state
        (princ$
         (string-arrayi (- (string-array-length text-store) len)
                        text-store)
         channel state)))
    (string-array-to-output-channel-helper text-store (- len 1)
                                           channel state)))

(encapsulate
  ()

  (local (include-book "rtl/rel9/arithmetic/top" :dir :system))

  (defun
    fill-string-array
    (text-store str len)
    (declare
     (xargs
      :guard (and (stringp str)
                  (natp len)
                  (<= len
                      (string-array-length text-store))
                  (<
                   (string-array-length text-store)
                   (ash 1 28))
                  (equal (length str)
                         (* (string-array-length text-store) 1024)))
      :guard-hints
      (("goal"))
      :stobjs text-store))
    (b*
        ((len (the (unsigned-byte 28) len)))
      (if
          (zp len)
          text-store
       (b*
           ((cluster-size 1024)
            (index (- (string-array-length text-store)
                      len))
            (current-cluster (subseq str (* index cluster-size)
                                     (* (+ index 1) cluster-size)))
            (text-store
             (update-string-arrayi
              index current-cluster text-store)))
         (fill-string-array
          text-store str
          (the (unsigned-byte 28) (- len 1))))))))

(b*
    ((str (read-file-into-string "big.file"))
     (text-store
      (resize-string-array
        (floor (length str) 1024)
        text-store))
     (text-store
      (fill-string-array
       text-store str (floor (length str) 1024))))
  text-store)

(b*
    (((mv channel state)
      (open-output-channel "test.txt" :character state))
     (state
      (time$
       (string-array-to-output-channel-helper
        text-store (string-array-length text-store) channel state)))
     (state
      (close-output-channel channel state)))
  state)

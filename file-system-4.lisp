(in-package "ACL2")

;  file-system-4.lisp                                  Mihir Mehta

; Here we define a more complex file system with a disk and an allocation bitmap.
; We first start with a file-system recognizer, and then we define various
; file-system operations.

(include-book "file-system-3")

(defun find-n-free-blocks (disk alv n start)
  (declare (xargs :guard (and (block-listp disk)
                              (boolean-listp alv)
                              (equal (len disk) (len alv))
                              (natp n)
                              (natp start))))
  (if (or (atom alv) (zp n))
      nil
    (if (car alv)
        ;; this block is taken
        (find-n-free-blocks (cdr disk) (cdr alv) n (+ start 1))
      ;; this block isn't taken
      (cons start (find-n-free-blocks (cdr disk) (cdr alv) (- n 1) (+ start 1))))))

;; Here are some examples showing how this works.
;; ACL2 !>(find-n-free-blocks (list *nullblock* *nullblock* *nullblock*) (list t nil t) 1 0)
;; (1)
;; ACL2 !>(find-n-free-blocks (list *nullblock* *nullblock* *nullblock*) (list t nil t) 2 0)
;; (1)
;; ACL2 !>(find-n-free-blocks (list *nullblock* *nullblock* *nullblock*) (list t nil nil) 2 0)
;; (1 2)


(defthm find-n-free-blocks-correctness-1
  (implies (and (boolean-listp alv)
                (natp n))
           (<= (len (find-n-free-blocks disk alv n start)) n))
  :rule-classes (:rewrite :linear))

(defun count-free-blocks (alv)
  (declare (xargs :guard (and (boolean-listp alv))))
  (if (atom alv)
      0
    (if (car alv)
        (count-free-blocks (cdr alv))
      (+ (count-free-blocks (cdr alv)) 1))))

(defthm find-n-free-blocks-correctness-2
  (implies (and (boolean-listp alv)
                (natp n)
                (<= n (count-free-blocks alv)))
           (equal (len (find-n-free-blocks disk alv n start)) n)))

(encapsulate
  ( ((set-indices-in-alv * * *) => *) )

  (local
   (defun set-indices-in-alv-helper (alv index-list value offset)
     (declare (xargs :guard (and (boolean-listp alv)
                                 (nat-listp index-list)
                                 (booleanp value)
                                 (natp offset))))
     (if (atom alv)
         nil
       (let ((tail (set-indices-in-alv-helper
                    (cdr alv)
                    index-list value (+ offset 1))))
         (if (member offset index-list)
             (cons value tail)
           (cons (car alv) tail))))))

  (local
   (defthm
     set-indices-in-alv-helper-correctness-1
     (implies
      (and (boolean-listp alv)
           (booleanp value))
      (boolean-listp (set-indices-in-alv-helper alv index-list value offset)))
     :rule-classes (:type-prescription :rewrite)))

  (local
   (defthm
     set-indices-in-alv-helper-correctness-2
     (implies
      (boolean-listp alv)
      (equal (len (set-indices-in-alv-helper alv index-list value offset))
             (len alv)))))

  (local
   (defthm
     set-indices-in-alv-helper-correctness-3
     (implies
      (and (boolean-listp alv)
           (nat-listp index-list)
           (booleanp value)
           (natp offset)
           (member-equal n index-list)
           (>= n offset)
           (< n (+ offset (len alv))))
      (equal (nth (- n offset)
                  (set-indices-in-alv-helper alv index-list value offset))
             value))))

  (local
   (defthm
     set-indices-in-alv-helper-correctness-4
     (implies
      (and (boolean-listp alv)
           (nat-listp index-list)
           (booleanp value)
           (natp offset)
           (natp n)
           (not (member-equal n index-list))
           (>= n offset)
           (< n (+ offset (len alv))))
      (equal (nth (- n offset)
                  (set-indices-in-alv-helper alv index-list value offset))
             (nth (- n offset) alv)))))

  (local
   (defun set-indices-in-alv (alv index-list value)
     (declare (xargs :guard (and (boolean-listp alv)
                                 (nat-listp index-list)
                                 (booleanp value))))
     (set-indices-in-alv-helper alv index-list value 0)))

  (defthm
    set-indices-in-alv-correctness-1
    (implies
     (and (boolean-listp alv)
          (booleanp value))
     (boolean-listp (set-indices-in-alv alv index-list value)))
    :rule-classes (:type-prescription :rewrite))

  (defthm
    set-indices-in-alv-correctness-2
    (implies
     (boolean-listp alv)
     (equal (len (set-indices-in-alv alv index-list value))
            (len alv))))

  (defthm
    set-indices-in-alv-correctness-3
    (implies
     (and (boolean-listp alv)
          (nat-listp index-list)
          (booleanp value)
          (member-equal n index-list)
          (< n (len alv)))
     (equal (nth n
                 (set-indices-in-alv alv index-list value))
            value))
    :hints (("Goal" :in-theory (disable set-indices-in-alv-helper-correctness-3)
             :use (:instance set-indices-in-alv-helper-correctness-3
                             (offset 0))) ))

  (defthm
    set-indices-in-alv-correctness-4
    (implies
     (and (boolean-listp alv)
          (nat-listp index-list)
          (booleanp value)
          (natp offset)
          (natp n)
          (not (member-equal n index-list))
          (< n (len alv)))
     (equal (nth n
                 (set-indices-in-alv alv index-list value))
            (nth n alv)))
    :hints (("Goal" :in-theory (disable set-indices-in-alv-helper-correctness-4)
             :use (:instance set-indices-in-alv-helper-correctness-4
                             (offset 0))) )))

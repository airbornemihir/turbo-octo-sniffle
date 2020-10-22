(in-package "ACL2")

;  member-intersectp.lisp                              Mihir Mehta

(include-book "not-intersectp-list")

(defun disjoint-list-listp (x)
  (if (atom x)
      (equal x nil)
    (and (not-intersectp-list (car x) (cdr x))
         (disjoint-list-listp (cdr x)))))

(defun no-duplicates-listp (x)
  (if (atom x)
      (equal x nil)
    (and (no-duplicatesp (car x)) (no-duplicates-listp (cdr x)))))

(defthm flatten-disjoint-lists
  (implies (true-listp l)
           (equal (no-duplicatesp-equal (flatten l))
                  (and (disjoint-list-listp l) (no-duplicates-listp l)))))

(defthm not-intersectp-list-of-append-2
  (equal (not-intersectp-list (binary-append x y) l)
         (and (not-intersectp-list x l)
              (not-intersectp-list y l)))
  :hints (("Goal" :in-theory (enable not-intersectp-list))))

(defthm no-duplicates-listp-of-append
  (equal (no-duplicates-listp (binary-append x y))
         (and (no-duplicates-listp (true-list-fix x))
              (no-duplicates-listp y))))

(defthm
  not-intersectp-list-of-cons-1
  (implies (case-split (consp y))
           (equal (not-intersectp-list (cons x y) l)
                  (and (not-intersectp-list (list x) l)
                       (not-intersectp-list y l))))
  :hints
  (("goal" :do-not-induct t
    :in-theory (disable not-intersectp-list-of-append-2)
    :use (:instance not-intersectp-list-of-append-2
                    (x (list x))))))

(defun member-intersectp-equal (x y)
  (declare (xargs :guard (and (true-list-listp x) (true-list-listp y))))
  (and (consp x)
       (or (not (not-intersectp-list (car x) y))
           (member-intersectp-equal (cdr x) y))))

(defcong list-equiv
  equal (member-intersectp-equal x y)
  1
  :hints (("goal" :in-theory (enable fast-list-equiv)
           :induct (fast-list-equiv x x-equiv))))

(defthm when-append-is-disjoint-list-listp
  (equal (disjoint-list-listp (binary-append x y))
         (and (disjoint-list-listp (true-list-fix x))
              (disjoint-list-listp y)
              (not (member-intersectp-equal x y)))))

(defthm member-intersectp-with-subset
  (implies (and (member-intersectp-equal z x)
                (subsetp-equal x y))
           (member-intersectp-equal z y)))

(defthm
  intersectp-member-when-not-member-intersectp
  (implies (and (member-equal x lst2)
                (not (member-intersectp-equal lst1 lst2)))
           (not-intersectp-list x lst1))
  :hints (("Goal" :in-theory (enable not-intersectp-list))))

(local
 (defthm member-intersectp-binary-append-lemma
   (equal (member-intersectp-equal e (binary-append x y))
          (or (member-intersectp-equal e x)
              (member-intersectp-equal e y)))))

(local
 (defthm member-intersectp-is-commutative-lemma-1
   (implies (not (consp x))
            (not (member-intersectp-equal y x)))
   :hints (("Goal" :in-theory (enable not-intersectp-list)))))

(defthm member-intersectp-is-commutative-lemma-2
  (implies (and (consp x)
                (not (not-intersectp-list (car x) y)))
           (member-intersectp-equal y x))
  :hints (("Goal" :in-theory (enable not-intersectp-list))))

(defthmd member-intersectp-is-commutative-lemma-3
  (implies (and (consp x)
                (not-intersectp-list (car x) y))
           (equal (member-intersectp-equal y (cdr x))
                  (member-intersectp-equal y x)))
  :hints (("Goal" :in-theory (enable not-intersectp-list))))

(defthm member-intersectp-is-commutative
  (equal (member-intersectp-equal x y)
         (member-intersectp-equal y x))
  :hints (("Goal" :in-theory (enable member-intersectp-is-commutative-lemma-3)) ))

(defthm
  another-lemma-about-member-intersectp
  (implies (or (member-intersectp-equal x z)
               (member-intersectp-equal y z))
           (member-intersectp-equal z (binary-append x y))))

(defthm member-intersectp-binary-append
  (equal (member-intersectp-equal e (binary-append x y))
         (or (member-intersectp-equal e x)
             (member-intersectp-equal e y)))
  :rule-classes
  (:rewrite
   (:rewrite
    :corollary
    (equal (member-intersectp-equal (binary-append x y) e)
           (or (member-intersectp-equal x e)
               (member-intersectp-equal y e))))))

(defthm not-intersectp-list-of-flatten
  (equal (not-intersectp-list (flatten x) y)
         (not (member-intersectp-equal x y))))
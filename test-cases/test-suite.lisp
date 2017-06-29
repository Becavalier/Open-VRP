;;; A test suite for Open-VRP using FiveAM
(in-package :open-vrp.test)

(def-suite :suite-open-vrp)
(in-suite :suite-open-vrp)

;; Generic algo runs
;; --------------------------------------
(defmacro on-all-testcases (algo-symbol)
  (labels ((mkstr (&rest args)	   
	     (with-output-to-string (s)
	       (dolist (a args) (princ a s))))
	   (symb (&rest args)
	     (values (intern (apply #'mkstr args)))))
    `(progn
       (test ,(symb algo-symbol '-tsp) (is (solve-prob test-tsp (make-instance ,algo-symbol))))
       (test ,(symb algo-symbol '-vrp) (is (solve-prob test-vrp (make-instance ,algo-symbol))))
       (test ,(symb algo-symbol '-25) (is (solve-prob solomon25 (make-instance ,algo-symbol))))
       (test ,(symb algo-symbol '-100) (is (solve-prob solomon100 (make-instance ,algo-symbol))))
       (test ,(symb algo-symbol '-44) (is (solve-prob testpi (make-instance ,algo-symbol))))
       (test ,(symb algo-symbol '-chr1) (is (solve-prob christofides-1 (make-instance ,algo-symbol))))
       (test ,(symb algo-symbol '-chr2) (is (solve-prob christofides-2 (make-instance ,algo-symbol)))))))

;; routine tests
(on-all-testcases 'greedy-nn)
(on-all-testcases 'greedy-append)
(on-all-testcases 'greedy-best-insertion)
(on-all-testcases 'tabu-search)


;; special tabu-search tests

(test tabu-100 (is (solve-prob solomon100 (make-instance 'tabu-search :iterations 100))))

;; --------------------------------

;; Constraints checking tests
;; --------------------------------
;; Capacity
(defun space-v ()
  (make-vehicle
   :capacity 3
   :route (list (new-node 8 0 0 :demand 1)
		(new-node 9 1 1 :demand 1))))

(defun overfull-v ()
  (make-vehicle
   :capacity 2
   :route (list (new-node 0 0 0 :demand 1)
		(new-node 1 1 1 :demand 2))))

(test capacity-veh-in
  (is (in-capacityp (space-v))))

(test capacity-veh-out
  (is-false (in-capacityp (overfull-v))))

(test capacity-fleet-in
  (is (in-capacityp (make-instance 'cvrp :fleet (list (space-v) (space-v) (space-v))))))

(test capacity-fleet-out
  (is-false (in-capacityp (make-instance 'cvrp :fleet (list (overfull-v) (space-v))))))

;; Time Windows
(defun on-time-v ()
  (make-vehicle
   :speed 1
   :route (list
	   (new-node 1 1 0 :start 0 :end 2 :duration 1)
	   (new-node 2 2 0 :start 0 :end 2 :duration 1) 
	   (new-node 3 3 0 :start 5 :end 8 :duration 2)
	   (new-node 4 4 0 :start 0 :end 10 :duration 1))))

(defun late-v-duration ()
  (make-vehicle
   :speed 1
   :route (list
	   (new-node 1 1 0 :start 0 :end 2 :duration 0)
	   (new-node 2 2 0 :start 0 :end 2 :duration 10) 
	   (new-node 3 3 0 :start 5 :end 8 :duration 2)
	   (new-node 4 4 0 :start 0 :end 10 :duration 1))))

(defun late-v-speed ()
  (make-vehicle
   :speed 0.5
   :route (list
	   (new-node 1 1 0 :start 0 :end 2 :duration 1)
	   (new-node 2 2 0 :start 0 :end 2 :duration 1) 
	   (new-node 3 3 0 :start 5 :end 8 :duration 2)
	   (new-node 4 4 0 :start 0 :end 8 :duration 1))))

(test time-window-test-on-time
  (is (veh-in-timep (on-time-v))))

(test time-window-test-too-late-duration
  (is-false (veh-in-timep (late-v-duration))))

(test time-window-test-too-late-speed
  (is-false (veh-in-timep (late-v-speed))))

(test time-window-test-fleet-on-time
  (is (in-timep (make-instance 'vrptw :fleet (list (on-time-v) (on-time-v) (on-time-v))))))

(test time-window-test-fleet-late
  (is-false (in-timep (make-instance 'vrptw :fleet (list (on-time-v) (late-v-speed) (on-time-v))))))

;; Capacity AND Time Windows
(defun on-time-and-in-cap-v ()
  (make-vehicle
   :speed 1
   :capacity 10
   :route (list
	   (new-node 1 1 0 :start 0 :end 2 :duration 1 :demand 3)
	   (new-node 2 2 0 :start 0 :end 2 :duration 1 :demand 1) 
	   (new-node 3 3 0 :start 5 :end 8 :duration 2 :demand 1)
	   (new-node 4 4 0 :start 0 :end 10 :duration 1 :demand 1))))

(defun on-time-but-overfull-v ()
  (make-vehicle
   :speed 1
   :capacity 2
   :route (list
	   (new-node 1 1 0 :start 0 :end 2 :duration 1 :demand 3)
	   (new-node 2 2 0 :start 0 :end 2 :duration 1 :demand 1) 
	   (new-node 3 3 0 :start 5 :end 8 :duration 2 :demand 1)
	   (new-node 4 4 0 :start 0 :end 10 :duration 1 :demand 1))))


(test tw-and-cap-test-ok
  (is (constraintsp (make-instance 'cvrptw :fleet (list (on-time-and-in-cap-v) (on-time-and-in-cap-v))))))

(test tw-and-cap-test-fail
  (is-false (constraintsp (make-instance 'cvrptw :fleet (list (on-time-and-in-cap-v) (on-time-but-overfull-v))))))
;; -----------------------

;; Move feasibility checks
;; -----------------------

(test cap-move-feasible
  (is (feasible-movep (make-instance 'cvrp :fleet (list (space-v) (space-v)) :network (vector (new-node 1 1 1 :demand 1)))
		      (make-insertion-move :node-id 0 :vehicle-id 0))))

(test cap-move-infeasible
  (is-false (feasible-movep (make-instance 'cvrp :fleet (list (space-v) (space-v)) :network (vector (new-node 1 1 1 :demand 5)))
			   (make-insertion-move :node-id 0 :vehicle-id 0))))
				     
(test tw-move-feasible
  (is (feasible-movep (make-instance 'vrptw :fleet (list (on-time-v) (on-time-v)) :network (vector (new-node 5 2 1 :start 3 :end 5 :duration 1)))
		      (make-insertion-move :node-id 0 :vehicle-id 0 :index 2))))

(test tw-move-infeasible
  (is-false (feasible-movep (make-instance 'vrptw :fleet (list (on-time-v) (on-time-v)) :network (vector (new-node 5 2 1 :start 3 :end 5 :duration 1)))
			   (make-insertion-move :node-id 0 :vehicle-id 0 :index 3))))

;; -----------------------

;; Asymmetric network
;; -----------------------

(defvar asym-net (define-problem "asym" 1 :demands '(0 1 1) :capacities 2 :to-depot nil :dist-matrix #2A((nil 1 5)(5 nil 1) (1 5 nil))))

(test asym-greedy-nn (is (solve-prob asym-net (make-instance 'greedy-nn))))
(test asym-greedy-append (is (solve-prob asym-net (make-instance 'greedy-append))))
(test asym-greedy-best-insertion (is (solve-prob asym-net (make-instance 'greedy-best-insertion))))
(test asym-tabu-search (is (solve-prob asym-net (make-instance 'tabu-search))))


(defvar asym-tsp (define-problem "asym" 1 :dist-matrix #2A((nil 1 5)(5 nil 1) (1 5 nil))))

(test asym-greedy-nn (is (solve-prob asym-tsp (make-instance 'greedy-nn))))
(test asym-greedy-append (is (solve-prob asym-tsp (make-instance 'greedy-append))))
(test asym-greedy-best-insertion (is (solve-prob asym-tsp (make-instance 'greedy-best-insertion))))
(test asym-tabu-search (is (solve-prob asym-tsp (make-instance 'tabu-search))))

(defvar asym-vrp (define-problem "asym-vrp" 1 :dist-matrix #2A((nil 1 2)(1 nil 3)(2 3 nil)) :time-windows-list '((0 . 10)(2 . 5)(5 . 10)) :log-mode 0))

(test asym-vrp-perform-move
  (is (perform-move asym-vrp
                    (make-insertion-move :node-id 1 :vehicle-id 0 :index 1))))

(test tw-move-infeasible
  (is-false (feasible-movep asym-vrp                            
                            (make-insertion-move :node-id 2 :vehicle-id 0 :index 1))))

(test tw-move-feasible
  (is (feasible-movep asym-vrp                            
                      (make-insertion-move :node-id 2 :vehicle-id 0 :index 2))))

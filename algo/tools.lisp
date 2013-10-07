;;; Tools to be shared among algorithms
;;; ---------------------------
;;; 0. Miscellaneous
;;; 1. Move feasibility checks
;;; 2. Heuristical tools

(in-package :open-vrp.algo)

;; 0. Misc
;; -------------------------
(defstruct move fitness)

(defstruct (insertion-move (:include move) (:conc-name move-)) node-ID vehicle-ID index)

(defun route-from (ins-move sol)
  "Returns the route that contains the node that will be moved."
  (vehicle-route (vehicle sol (vehicle-with-node-ID sol (move-node-id ins-move)))))

(defun route-to (ins-move sol)
  "Returns the route that will be affected by the insertion-move."
  (vehicle-route (vehicle sol (move-vehicle-ID ins-move))))

(defun num-nodes (prob)
  "Given a problem, return the number of nodes in the network."
  (length (problem-network prob)))

(defun num-veh (prob)
  "Given a problem, return size of the fleet."
  (length (problem-fleet prob)))

;; --------------------------

;; 1. Feasibility check of moves
;; ---------------------------

(defgeneric feasible-movep (sol move)
  (:documentation "Given a current solution, assess feasibility of the <Move>. For CVRP, just check if it fits in the total vehicle capacity. For VRPTW, check for TW feasibility of the whole route. For CVRPTW, checks both by means of multiple-inheritance and method-combination.")
  (:method-combination and))

(defmethod feasible-movep and ((sol problem) (m move)) T)

(defmethod feasible-movep and ((sol CVRP) (m insertion-move))
  (with-slots (node-ID vehicle-ID) m
    (let ((veh (vehicle sol vehicle-ID)))
      ; if node is already on the route, moving intra-route is feasible
      (if (node-on-routep node-ID veh) T
          (multiple-value-bind (comply cap-left) (in-capacity-p veh)
            (unless comply (error 'infeasible-solution :sol sol :func #'in-capacity-p))
            (<= (node-demand (node sol node-ID)) cap-left))))))

(defmethod feasible-movep and ((sol VRPTW) (m insertion-move))
  (let ((node-id (move-node-id m))
        (veh-id (move-vehicle-id m))
        (index (move-index m)))
    (symbol-macrolet ((full-route (vehicle-route (vehicle sol veh-id)))
                      (ins-node (node sol node-ID))
                      (to (if (= 1 i) ins-node (car route)))
                      (arr-time (+ time (travel-time loc to :dist-array (problem-dist-array sol)))))
      (constraints-check
       (route time loc i)
       ((cdr full-route) 0 (car full-route) index)
       ((if (= 1 i) route (cdr route)) ;don't skip after inserting new node
        (time-after-visit to arr-time) ;set time after new node
        to (1- i))
       (<= arr-time (node-end to))
       (and (null route) (< i 1)))))) ; case of append, need to check once more

;; for debugging (insert in test-form with progn)
;       (format t "Route: ~A~% Loc: ~A~% To: ~A~% Time: ~A~% Arr-time: ~A~% Node-start: ~A~% Node-end: ~A~% Duration: ~A~% ins-node-end: ~A~% i: ~A~%" (mapcar #'node-id route) (node-id loc) (node-id to) time arr-time (node-start to) (node-end to) (node-duration to) (node-end ins-node) i)
;; -----------------------------

;; ----------------------------

;; 2. Tools for solution building heuristics
;; ---------------------------

;; Closest node (used by Greedy Nearest Neighborhood)
;; ---------------------------

(defun get-min-index-with-tabu (distances tabu)
  "Returns index of the first next closest, that is not in chosen (which is a list)."
  (with-tabu-indices tabu #'get-min-index distances))

(defun get-closest-node (prob veh-id &optional tabu)
  "Returns the closest node from the last location of vehicle. Requires <problem> and vehicle-ID. A tabu list of node-IDs is optional to exclude consideration of some nodes."
  (let* ((loc (last-node (vehicle prob veh-id)))
         (dists (get-array-row (problem-dist-array prob) (node-id loc))))
    (aif (get-min-index-with-tabu dists tabu)
         (node prob it)
         nil)))
;; --------------------------

;; Closest Vehicle (used by Greedy Append)
;; ---------------------------
(defun dists-to-vehicles (node prob)
  "Given a <Node> and a <Problem>, return the list of all the distances from the <Node> to the current positions of the fleet. Used by get-closest-(feasible)-vehicle."
  (mapcar #'(lambda (x) (distance (node-id (last-node x))
                                  (node-id node)
                                  (problem-dist-array prob)))
          (problem-fleet prob)))

;; challenge: what if the vehicle is located on the node n - use only for initial insertion?
(defun get-closest-vehicle (n prob)
  "Returns the closest <vehicle> to <node>. Used by insertion heuristic. When multiple <vehicle> are on equal distance, choose first one (i.e. lowest ID)."
  (vehicle prob (get-min-index (dists-to-vehicles n prob))))
;; -------------------------

;; Closest Feasible Vehicle
;; ----------------------------
(defmethod get-closest-feasible-vehicle ((n node) (prob problem))
  (get-closest-vehicle n prob))

;; Capacity check
(defun capacities-left (prob)
  "Returns a list of all capacities left on the vehicles given the present solution."
  (mapcar #'(lambda (x) (multiple-value-bind (c cap)
                            (in-capacity-p x) (when c cap)))
          (problem-fleet prob)))

(defmethod get-closest-feasible-vehicle ((n node) (prob CVRP))
  "Returns the vehicle closest to the node and has enough capacity."
  (handler-case
      (vehicle prob (get-min-index
                     (mapcar #'(lambda (dist cap)
                                 (unless (> (node-demand n) cap) dist))
                             (dists-to-vehicles n prob)
                             (capacities-left prob))))
    (list-of-nils () (error 'no-feasible-move :moves n))))


;; Time-window check
(defun times-of-arriving (node prob)
  "Returns a list of arrival times of the vehicles to node given the present solution."
  (mapcar #'(lambda (x)
              (multiple-value-bind (c time)
                  (veh-in-timep x) (when c (+ time (travel-time (last-node x) node :dist-array (problem-dist-array prob))))))
          (problem-fleet prob)))

;; Feasiblility of appending at the end only.
(defmethod get-closest-feasible-vehicle ((n node) (prob VRPTW))
  "Returns the vehicle closest to the node that has enough time at the end of its route. Used for appending nodes. Use get-optimal-insertion instead for inserting feasibly into routes."
  (handler-case
      (vehicle prob (get-min-index
                     (mapcar #'(lambda (dist arr-time cap)
                                 (unless (or (> (node-demand n) cap)
                                             (> arr-time (node-end n)))
                                   dist))
                             (dists-to-vehicles n prob)
                             (times-of-arriving n prob)
                             (capacities-left prob))))
    (list-of-nils () (error 'no-feasible-move :moves n))))

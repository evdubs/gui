#lang scheme/base

#|

This library is the part of the 2htdp/image 
teachpack that has to be shared between drscheme
and the user's program to make copy and paste
work right.

Most of the exports are just for use in 2htdp/image
(technically, 2htdp/private/image-more). The main
use of this library is the snip class addition it
does (and any code that that does not depend on
has been moved out).


-- in the middle of text:

  - bounding boxes
  - rotating (and bounding boxes)
  - hbl append(?)
  - this doesn't work (how to test?)
(beside/places "baseline"
                 (text "ijy" 12 'black)
                 (text "ijy" 24 'black))
|#

(require scheme/class
         scheme/gui/base
         scheme/math
         (for-syntax scheme/base))

(define-for-syntax id-constructor-pairs '())
(define-for-syntax (add-id-constructor-pair a b)
  (set! id-constructor-pairs (cons (list a b) id-constructor-pairs)))

(define-syntax (define-struct/reg-mk stx)
  (syntax-case stx ()
    [(_ id . rest)
     (let ([build-name
            (λ (fmt)
              (datum->syntax #'id (string->symbol (format fmt (syntax->datum #'id)))))])
       (add-id-constructor-pair (build-name "struct:~a")
                                (build-name "make-~a"))
       #'(define-struct id . rest))]))

(define-syntax (define-id->constructor stx)
  (syntax-case stx ()
    [(_ fn)
     #`(define (fn x)
         (case x
           #,@(map (λ (x) 
                     (with-syntax ([(struct: maker) x])
                       #`[(struct:) maker]))
                   id-constructor-pairs)))]))

(define-struct/reg-mk point (x y) #:transparent)


;                                                                
;                                                                
;                                                                
;                                                                
;                                                                
;                                                                
;       ;;           ;;                  ;;           ;;;        
;       ;;          ;;;                  ;;          ;;;         
;    ;;;;;   ;;;;  ;;;;;  ;;;;        ;;;;;   ;;;;  ;;;;; ;; ;;; 
;   ;;;;;;  ;;  ;;  ;;;; ;;  ;;      ;;;;;;  ;;  ;; ;;;;  ;;;;;; 
;  ;;;  ;;    ;;;;  ;;;    ;;;;     ;;;  ;; ;;;;;;;; ;;   ;;  ;; 
;  ;;;  ;;  ;;; ;;  ;;;  ;;; ;;     ;;;  ;; ;;;      ;;   ;;  ;; 
;   ;;;;;; ;;;  ;;  ;;;;;;;  ;;      ;;;;;;  ;;; ;;  ;;   ;;  ;; 
;    ;;;;;  ;;;;;;   ;;; ;;;;;;       ;;;;;   ;;;;   ;;   ;;  ;; 
;                                                                
;                                                                
;                                                                
;                                                         


;; a image is 
;;  (make-image shape bb boolean)
;; NOTE: the shape field is mutated when normalized, as
;;       is the normalized? field.
(define (make-image shape bb normalized?) (new image% [shape shape] [bb bb] [normalized? normalized?]))
(define (image-shape p) (send p get-shape))
(define (image-bb p) (send p get-bb))
(define (image-normalized? p) (send p get-normalized?))
(define (set-image-shape! p s) (send p set-shape s))
(define (set-image-normalized?! p n?) (send p set-normalized? n?))
(define (image-right image) (bb-right (image-bb image)))
(define (image-bottom image) (bb-bottom (image-bb image)))
(define (image-baseline image) (bb-baseline (image-bb image)))
(define (image? p) 
  (or (is-a? p image%)
      (is-a? p image-snip%)
      (is-a? p bitmap%)))


;; a bb is  (bounding box)
;;  (make-bb number number number)
(define-struct/reg-mk bb (right bottom baseline) #:transparent)

;; a shape is either:
;;
;;  - (make-overlay shape shape)
;;    the shapes are in the order passed to the overlay or beside,
;;    which means the bottom one should be drawn first so as to appear
;;    underneath the top one.
(define-struct/reg-mk overlay (top bottom) #:transparent #:omit-define-syntaxes) 
;;
;;  - (make-translate dx dy shape)
(define-struct/reg-mk translate (dx dy shape) #:transparent #:omit-define-syntaxes)
;;
;;  - (make-scale x-factor y-factor shape)
(define-struct/reg-mk scale (x y shape) #:transparent #:omit-define-syntaxes)
;;
;;  - atomic-shape

;; an atomic-shape is either:
;;  - polygon
;;  - np-atomic-shape

;; a np-atomic-shape is:
;;
;;  - (make-ellipse width height angle mode color)
(define-struct/reg-mk ellipse (width height angle mode color) #:transparent #:omit-define-syntaxes)
;;
;;  - (make-text string angle number color
;;               number (or/c #f string) family (or/c 'normal 'italic) (or/c 'normal 'light 'bold) boolean)
;;    NOTE: font can't be the raw mred font or else copy & paste won't work
(define-struct/reg-mk text (string angle y-scale color size face family style weight underline) 
  #:omit-define-syntaxes #:transparent)
;;
;;  - (make-bitmap (is-a?/c bitmap%) angle positive-real (or/c #f (is-a?/c bitmap%)))
;;    NOTE: bitmap copying needs to happen in 'write' and 'read' methods
(define-struct/reg-mk bitmap (raw-bitmap raw-mask angle scale rendered-bitmap) #:omit-define-syntaxes #:transparent)

;; a polygon is:
;;
;;  - (make-polygon (listof vector) mode color)
(define-struct/reg-mk polygon (points mode color) #:transparent #:omit-define-syntaxes
  #:property prop:equal+hash 
  (list (λ (a b rec) (polygon-equal? a b rec)) (λ (x y) 42) (λ (x y) 3)))

;; a normalized-shape (subtype of shape) is either
;;  - (make-overlay normalized-shape simple-shape)
;;  - simple-shape

;; a simple-shape (subtype of shape) is
;;  - (make-translate dx dy np-atomic-shape)
;;  - polygon

;; an angle is a number between 0 and 360 (degrees)

;; a mode is either 'solid or 'outline (indicating a pen width for outline mode)

(define (polygon-equal? p1 p2 eq-recur)
  (and (eq-recur (polygon-mode p1) (polygon-mode p2))
       (eq-recur (polygon-color p1) (polygon-color p2))
       (let ([p1-points (polygon-points p1)]
             [p2-points (polygon-points p2)])
         (or (and (null? p1-points)
                  (null? p2-points))
             (and (not (or (null? p1-points)
                           (null? p2-points)))
                  (or (eq-recur (rotate-to-zero (closest-to-zero p1-points) p1-points)
                                (rotate-to-zero (closest-to-zero p2-points) p2-points))
                      (let ([p1-rev (reverse p1-points)])
                        (eq-recur (rotate-to-zero (closest-to-zero p1-rev) p1-rev)
                                  (rotate-to-zero (closest-to-zero p2-points) p2-points)))))))))

(define (rotate-to-zero zero-p points)
  (let loop ([points points]
             [acc null])
    (cond
      [(equal? (car points) zero-p)
       (append points (reverse acc))]
      [else
       (loop (cdr points)
             (cons (car points) acc))])))

(define (closest-to-zero points)
  (car (sort points < #:key (λ (p) (+ (point-x p) (point-y p))))))


;                                                   
;                                                   
;                                                   
;   ;;                                    ;;   ;;   
;   ;;                                   ;;;;  ;    
;   ;                                    ; ;; ;     
;   ;;  ;;;;;;;;; ;;;;;   ;;;;;;  ;;;;   ; ;; ;     
;   ;;  ;; ;;; ;;;;   ;;  ;; ;;  ;;; ;;   ;; ;      
;   ;;  ;; ;;; ;;;  ;;;; ;;; ;;  ;;;;;;      ; ;;;  
;   ;;  ;; ;;; ;;;;;  ;;   ;;;   ;;          ;;; ;; 
;   ;;  ;; ;;; ;;;;;  ;;  ;;;;;  ;;;  ;     ; ;; ;; 
;   ;;  ;; ;;; ;;;;;;;;;; ;;;;;;  ;;;;     ;;  ;;;  
;                        ;;   ;;                    
;                        ;;   ;                     
;                         ;;;;                      

(define-local-member-name get-shape set-shape get-bb get-normalized? set-normalized get-normalized-shape)

(define image%
  (class* snip% (equal<%>)
    (init-field shape bb normalized?)
    (define/public (equal-to? that eq-recur) 
      (eq-recur (get-normalized-shape)
                (send that get-normalized-shape)))
    (define/public (equal-hash-code-of y) 42)
    (define/public (equal-secondary-hash-code-of y) 3)

    (define/public (get-shape) shape)
    (define/public (set-shape s) (set! shape s))
    (define/public (get-bb) bb)
    (define/public (get-normalized?) normalized?)
    (define/public (set-normalized? n?) (set! normalized? n?))
    
    (define/public (get-normalized-shape)
      (unless normalized?
        (set! shape (normalize-shape shape values))
        (set! normalized? #t))
      shape)
    
    (define/override (copy) (make-image shape bb normalized?))
    (define/override (draw dc x y left top right bottom dx dy draw-caret?)
      (let ([smoothing (send dc get-smoothing)])
        (send dc set-smoothing 'aligned)
        (render-image this dc x y)
        (send dc set-smoothing smoothing)))
    (define/override (get-extent dc x y [w #f] [h #f] [descent #f] [space #f] [lspace #f] [rspace #f])
      (send (get-the-snip-class-list) add snip-class)
      (let ([bottom (bb-bottom bb)])
        (set-box/f! w (bb-right bb))
        (set-box/f! h bottom)
        (set-box/f! descent (- bottom (bb-baseline bb)))
        (set-box/f! space 0)
        (set-box/f! lspace 0)
        (set-box/f! rspace 0)))

    (define/override (write f) 
      (let ([bytes (string->bytes/utf-8 (format "~s" (list shape bb)))])
        (send f put (bytes-length bytes) bytes)))
    
    (super-new)
    
    (inherit set-snipclass)
    (set-snipclass snip-class)))

(define scheme/base:read read)

(define image-snipclass% 
  (class snip-class%
    (define/override (read f)
      (let* ([bytes (send f get-unterminated-bytes)]
             [str 
              (and bytes
                   (with-handlers ((exn:fail? (λ (x) #f)))
                     (bytes->string/utf-8 bytes)))]
             [lst 
              (and str
                   (with-handlers ((exn:fail:read? (λ (x) #f)))
                     (parse 
                      (scheme/base:read
                       (open-input-string
                        str)))))])
        (if lst
            (make-image (list-ref lst 0)
                        (list-ref lst 1)
                        #f)
            (make-image (make-ellipse 100 100 0 'solid "black")
                        (make-bb 100 100 100)
                        #f))))
    (super-new)))

(provide snip-class) 
(define snip-class (new image-snipclass%))
(send snip-class set-classname (format "~s" '(lib "image-core.ss" "2htdp" "private")))
(send snip-class set-version 1)
(send (get-the-snip-class-list) add snip-class)

(define (set-box/f! b v) (when (box? b) (set-box! b v)))
 
(define (parse sexp)
  (let/ec k
    (let loop ([sexp sexp])
      (cond
        [(pair? sexp) (cons (loop (car sexp)) (loop (cdr sexp)))]
        [(vector? sexp)
         (if (= (vector-length sexp) 0)
             (k #f)
             (let ([constructor (id->constructor (vector-ref sexp 0))]
                   [args (cdr (vector->list sexp))])
               (if (and constructor
                        (procedure-arity-includes? constructor (length args)))
                   (apply constructor (map loop args))
                   (k #f))))]
        [else sexp]))))

(define-id->constructor id->constructor)

;; normalize-shape : shape (atomic-shape -> atomic-shape) -> normalized-shape
;; normalizes 'shape', calling 'f' on each atomic shape in the normalized shape.
(define (normalize-shape shape [f values])
  (let loop ([shape shape]
             [dx 0]
             [dy 0]
             [x-scale 1]
             [y-scale 1]
             [bottom #f])
    (cond
      [(translate? shape)
       (loop (translate-shape shape)
             (+ dx (* x-scale (translate-dx shape)))
             (+ dy (* y-scale (translate-dy shape)))
             x-scale
             y-scale
             bottom)]
      [(scale? shape)
       (loop (scale-shape shape)
             dx
             dy
             (* x-scale (scale-x shape))
             (* y-scale (scale-y shape))
             bottom)]
      [(overlay? shape)
       (loop (overlay-bottom shape)
             dx dy x-scale y-scale
             (loop (overlay-top shape)
                   dx dy x-scale y-scale bottom))]
      [(polygon? shape)
       (let* ([scaled-points
               (map (λ (p)
                      (make-point (+ dx (* x-scale (point-x p)))
                                  (+ dy (* y-scale (point-y p)))))
                    (polygon-points shape))]
              [this-one 
               (make-polygon scaled-points
                             (polygon-mode shape)
                             (polygon-color shape))])
         (if bottom
             (make-overlay bottom (f this-one))
             (f this-one)))]
      [(np-atomic-shape? shape)
       (let ([this-one (make-translate dx dy (scale-np-atomic x-scale y-scale shape))])
         (if bottom
             (make-overlay bottom (f this-one))
             (f this-one)))]
      [else 
       (error 'normalize-shape "unknown shape ~s\n" shape)])))

(define (atomic-shape? shape)
  (or (polygon? shape)
      (np-atomic-shape? shape)))

(define (np-atomic-shape? shape)
  (or (ellipse? shape)
      (text? shape)
      (bitmap? shape)
      (point? shape)))

(define (scale-np-atomic x-scale y-scale shape)
  (cond
    [(ellipse? shape)
     (make-ellipse (* x-scale (ellipse-width shape))
                   (* y-scale (ellipse-height shape))
                   (ellipse-angle shape)
                   (ellipse-mode shape)
                   (ellipse-color shape))]
    [(text? shape)
     ;; should probably do something different here so that
     ;; the y-scale is always greater than 1
     ;; (or else always smaller than 1)
     (make-text (text-string shape)
                (text-angle shape)
                (* (text-y-scale shape) (/ y-scale x-scale))
                (text-color shape)
                (* (text-size shape) x-scale)
                (text-face shape)
                (text-family shape)
                (text-style shape)
                (text-weight shape)
                (text-underline shape))]
    [(bitmap? shape) 
     (unless (and (= 1 x-scale)
                  (= 1 y-scale))
       (fprintf (current-error-port) "scaling a bitmap, ignoring\n"))
     shape]))


;                                                                
;                                                                
;                                                                
;                                                                
;                                                                
;                                                                
;                            ;;               ;;                 
;                            ;;               ;;                 
;   ;;;;  ;;;;   ;; ;;;   ;;;;;   ;;;;   ;;;;;;;  ;; ;;;  ;;;;;; 
;   ;;;; ;;  ;;  ;;;;;;  ;;;;;;  ;;  ;;  ;;;; ;;  ;;;;;;  ;;;;;; 
;   ;;  ;;;;;;;; ;;  ;; ;;;  ;; ;;;;;;;; ;;   ;;  ;;  ;; ;;;  ;; 
;   ;;  ;;;      ;;  ;; ;;;  ;; ;;;      ;;   ;;  ;;  ;; ;;;  ;; 
;   ;;   ;;; ;;  ;;  ;;  ;;;;;;  ;;; ;;  ;;   ;;  ;;  ;;  ;;;;;; 
;   ;;    ;;;;   ;;  ;;   ;;;;;   ;;;;   ;;   ;;  ;;  ;;   ;;;;; 
;                                                         ;; ;;; 
;                                                         ;;;;;  
;                                                                
;                                                         

;; render-image : normalized-shape dc dx dy -> void
(define (render-image image dc dx dy)
  (let ([pen (send dc get-pen)]
        [brush (send dc get-brush)]
        [font (send dc get-font)]
        [fg (send dc get-text-foreground)])
    (let loop ([shape (send image get-normalized-shape)])
      (cond
        [(overlay? shape)
         (render-simple-shape (overlay-bottom shape) dc dx dy)
         (loop (overlay-top shape))]
        [else
         (render-simple-shape shape dc dx dy)]))
    (send dc set-pen pen)
    (send dc set-brush brush)
    (send dc set-font font)
    (send dc set-text-foreground fg)))

(define (render-simple-shape simple-shape dc dx dy)
  (cond
    [(polygon? simple-shape)
     (let ([path (new dc-path%)]
           [points (polygon-points simple-shape)])
       (send path move-to (point-x (car points)) (point-y (car points)))
       (let loop ([point (make-rectangular (point-x (car points)) (point-y (car points)))]
                  [points (cdr points)])
         (unless (null? points)
           (let* ([vec (make-rectangular (- (point-x (car points))
                                            (real-part point))
                                         (- (point-y (car points))
                                            (imag-part point)))]
                  [endpoint (+ point vec (make-polar -1 (angle vec)))])
           (send path line-to (real-part endpoint) (imag-part endpoint))
           (loop endpoint (cdr points)))))
       (send path line-to (point-x (car points)) (point-y (car points)))
       (send dc set-pen (mode-color->pen (polygon-mode simple-shape) (polygon-color simple-shape)))
       (send dc set-brush (mode-color->brush (polygon-mode simple-shape) (polygon-color simple-shape)))
       (send dc draw-path path dx dy 'winding))]
    [else
     (let ([dx (+ dx (translate-dx simple-shape))]
           [dy (+ dy (translate-dy simple-shape))]
           [atomic-shape (translate-shape simple-shape)])
       (cond
         [(ellipse? atomic-shape)
          (let* ([path (new dc-path%)]
                 [ew (ellipse-width atomic-shape)]
                 [eh (ellipse-height atomic-shape)]
                 [θ (degrees->radians (ellipse-angle atomic-shape))])
            (let-values ([(rotated-width rotated-height) (ellipse-rotated-size ew eh θ)])
              (send path ellipse 0 0 ew eh)
              (send path translate (- (/ ew 2)) (- (/ eh 2)))
              (send path rotate θ)
              (send path translate (/ rotated-width 2) (/ rotated-height 2))
              (send dc set-pen (mode-color->pen (ellipse-mode atomic-shape) (ellipse-color atomic-shape)))
              (send dc set-brush (mode-color->brush (ellipse-mode atomic-shape) (ellipse-color atomic-shape)))
              (send dc draw-path path dx dy)))]
         [(bitmap? atomic-shape)
          (send dc draw-bitmap 
                (bitmap-raw-bitmap atomic-shape)
                dx dy
                'solid
                (send the-color-database find-color "black")
                (bitmap-raw-mask atomic-shape))]
         [(text? atomic-shape)
          (let ([θ (degrees->radians (text-angle atomic-shape))]
                [font (send dc get-font)])
            (send dc set-font (text->font atomic-shape))
            (send dc set-text-foreground 
                  (or (send the-color-database find-color (text-color atomic-shape))
                      (send the-color-database find-color "black")))
            (send dc draw-text (text-string atomic-shape) dx dy #f 0 θ))]))]))

(define (text->font text)
  (cond
    [(text-face text)
     (send the-font-list find-or-create-font
           (text-size text)
           (text-face text)
           (text-family text)
           (text-style text) 
           (text-weight text)
           (text-underline text))]
    [else
     (send the-font-list find-or-create-font
           (text-size text)
           (text-family text)
           (text-style text) 
           (text-weight text)
           (text-underline text))]))

(define (ellipse-rotated-size ew eh θ)
  (cond
    [(and (zero? ew) (zero? eh))
     (values 0 0)]
    [(zero? eh)
     (values (* (cos θ) ew)
             (* (sin θ) ew))]
    [(zero? ew)
     (values (* (sin θ) eh)
             (* (cos θ) eh))]
    [else
     (let* ([t1 (atan (/ eh ew (exact->inexact (tan θ))))]
            ; a*cos(t1),b*sin(t1) is the point on *original* ellipse which gets rotated to top.
            [t2 (atan (/ (* (- eh) (tan θ)) ew))] ; the original point rotated to right side.
            [rotated-height (+ (* ew (sin θ) (cos t1)) (* eh (cos θ) (sin t1)))]
            [rotated-width  (- (* ew (cos θ) (cos t2)) (* eh (sin θ) (sin t2)))])
       (values (abs rotated-width)
               (abs rotated-height)))]))

(define (degrees->radians θ)
  (* θ 2 pi (/ 360)))

(define (mode-color->pen mode color)
  (cond
    [(eq? mode 'solid)
     (send the-pen-list find-or-create-pen "black" 1 'transparent)]
    [else
     (send the-pen-list find-or-create-pen color 1 'solid)]))

(define (mode-color->brush mode color)
  (cond
    [(eq? mode 'solid)
     (send the-brush-list find-or-create-brush color 'solid)]
    [else
     (send the-brush-list find-or-create-brush "black" 'transparent)]))

(provide make-image image-shape image-bb image-normalized? image%
         
         (struct-out bb)
         (struct-out point)
         make-overlay overlay? overlay-top overlay-bottom
         make-translate translate? translate-dx translate-dy translate-shape
         make-scale scale-x scale-y scale-shape
         make-ellipse ellipse? ellipse-width ellipse-height ellipse-angle ellipse-mode ellipse-color
         make-text text? text-string text-angle text-y-scale text-color
         text-angle text-size text-face text-family text-style text-weight text-underline
         make-polygon polygon? polygon-points polygon-mode polygon-color
         make-bitmap bitmap? bitmap-raw-bitmap bitmap-raw-mask bitmap-angle bitmap-scale bitmap-rendered-bitmap
         
         degrees->radians
         normalize-shape
         ellipse-rotated-size
         
         image?
         image-right
         image-bottom
         image-baseline
         
         text->font
         
         render-image)

;; method names
(provide get-shape get-bb get-normalized?)
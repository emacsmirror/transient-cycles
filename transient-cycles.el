;;; transient-cycles.el --- Define command variants with transient cycling  -*- lexical-binding: t -*-

;; Copyright (C) 2020-2022  Free Software Foundation, Inc.

;; Author: Sean Whitton <spwhitton@spwhitton.name>
;; Maintainer: Sean Whitton <spwhitton@spwhitton.name>
;; Package-Requires: ((emacs "27.1"))
;; Version: 1.0
;; URL: https://git.spwhitton.name/dotfiles/tree/.emacs.d/site-lisp/transient-cycles.el
;; Keywords: buffer, window, minor-mode, convenience

;; This file is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this file.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Many commands can be conceptualised as selecting an item from an ordered
;; list or ring.  Sometimes after running such a command, you find that the
;; item selected is not the one you would have preferred, but the preferred
;; item is nearby in the list.  If the command has been augmented with
;; transient cycling, then it finishes by setting a transient map with keys to
;; move backwards and forwards in the list of items, so you can select a
;; nearby item instead of the one the command selected.  From the point of
;; view of commands subsequent to the deactivation of the transient map, it is
;; as though the first command actually selected the nearby item, not the one
;; it really selected.
;;
;; For example, suppose that you often use `eshell' with a prefix argument to
;; create multiple Eshell buffers, *eshell*, *eshell*<2>, *eshell*<3> and so
;; on.  When you use `switch-to-buffer' to switch to one of these buffers, you
;; will typically end up in the most recently used Eshell.  But sometimes what
;; you wanted was an older Eshell -- but which one?  It would be convenient to
;; quickly cycle through the other Eshell buffers when you discover that
;; `switch-to-buffer' took you to the wrong one.  That way, you don't need to
;; remember which numbered Eshell you were using to do what.
;;
;; In this example, we can think of `switch-to-buffer' as selecting from the
;; list of buffers in `eshell-mode'.  If we augment the command with transient
;; cycling, then you can use the next and previous keys in the transient map
;; to cycle through the `eshell-mode' buffers to get to the right one.
;; Afterwards, it is as though `switch-to-buffer' had taken you directly
;; there: the buffer list is undisturbed except for the target Eshell buffer
;; having been moved to the top, and only the target Eshell buffer is pushed
;; to the window's previous buffers (see `window-prev-buffers').
;;
;; This library provides macros to define variants of commands which have
;; transient cycling, and also some minor modes which replace some standard
;; Emacs commands with transient cycling variants the author has found useful.
;; `transient-cycles-buffer-siblings-mode' implements a slightly more complex
;; version of the transient cycling described in the above example.
;;
;; Definitions of command variants in this file only hide the fact that
;; transient cycling went on -- in the above example, how the buffer list is
;; undisturbed and how only the final buffer is pushed to the window's
;; previous buffers -- to the extent that doing so does not require saving a
;; lot of information when commencing transient cycling.

;;; News:

;; Ver 1.0 2022/04/10 Sean Whitton
;;     Initial release.
;;     Thanks to Protesilaos Stavrou for testing and docs feedback.

;;; Code:

(require 'ring)
(require 'subr-x)
(require 'cl-lib)

(defgroup transient-cycles nil
  "Defaults and options when defining variants of commands with
transient cycling."
  :group 'convenience)

(defcustom transient-cycles-show-cycling-keys t
  "Whether to show the cycling keys in the echo area when
commencing transient cycling."
  :type 'boolean
  :group 'transient-cycles)

(defcustom transient-cycles-default-cycle-backwards-key [left]
  "Default key for cycling backwards in the transient maps set by
commands to which transient cycling has been added."
  :type 'key-sequence
  :group 'transient-cycles)

(defcustom transient-cycles-default-cycle-forwards-key [right]
  "Default key for cycling forwards in the transient maps set by
commands to which transient cycling has been added."
  :type 'key-sequence
  :group 'transient-cycles)

(cl-defmacro transient-cycles-define-commands
    (bindings commands cycler-generator
     &key on-exit
       (cycle-forwards-key transient-cycles-default-cycle-forwards-key)
       (cycle-backwards-key transient-cycles-default-cycle-backwards-key)
       (keymap '(current-global-map)))
  "Define command variants closing over BINDINGS as specified by
COMMANDS with transient cycling as supplied by CYCLER-GENERATOR.

BINDINGS are established by means of `let*' at the beginning of
each command variant.  Thus each command variant,
CYCLER-GENERATOR and ON-EXIT all close over each of BINDINGS.
The storage is intended to last for the duration of transient
cycling, and may be used for cycling state or to save values from
before cycling began for restoration during ON-EXIT.

Each of COMMANDS defines a command variant, and should be of one
of the following forms:

1. (ORIGINAL ARGS [INTERACTIVE] &body BODY)

2. ORIGINAL alone, which means
   (ORIGINAL (&rest args) (apply ORIGINAL args)).

ORIGINAL can have one of the following forms:

a. a plain symbol

b. a pair (KEY . ORIGINAL) where ORIGINAL is a symbol

c. a vector [remap ORIGINAL] where ORIGINAL is a symbol, which
   means ([remap ORIGINAL] . ORIGINAL).

In each combination, ORIGINAL names the command for which a
transient cycling variant should be defined; ARGS, INTERACTIVE
and BODY are as in `lambda'; and KEY, if present, is a key
sequence to which the command should be bound in KEYMAP.  If
INTERACTIVE is absent then the newly defined command receives
ORIGINAL's interactive form.

CYCLER-GENERATOR defines a function which will be called with the
return value of each command variant, and must return a function
of one argument, which is known as the cycler.  After the call to
the command variant, a transient map is established in which
CYCLE-FORWARDS-KEY invokes the cycler with the numeric value of
the prefix argument and CYCLE-BACKWARDS-KEY invokes the cycler
with the numeric value of the prefix argument multiplied by -1.

CYCLE-FORWARDS-KEY and CYCLE-BACKWARDS-KEY are evaluated at the
time the transient map is established, so it is possible to
compute cycling keys from the binding used to invoke the command.
For example, for CYCLE-FORWARDS-KEY, you might have

    (cond ((memq last-command-event '(up down)) [down])
	  ((memq last-command-event '(left right)) [right])
	  (t transient-cycles-default-cycle-forwards-key))

ON-EXIT, if present, is wrapped in a lambda expression with no
arguments, i.e. (lambda () ON-EXIT), and passed as the third
argument to `set-transient-map'."
  (macroexp-progn
   (cl-loop with on-exit = (and on-exit `(lambda () ,on-exit))
	 and arg = (gensym) and cycler = (gensym) and tmap = (gensym)
	 and kforwards = (gensym) and kbackwards = (gensym)
	 for command in commands
	 for (original args . body)
	 = (if (proper-list-p command)
	       command
	     (let ((f (cl-etypecase command
			(symbol command)
			(cons (cdr command))
			(vector (aref command 1)))))
	       `(,command (&rest args) (apply #',f args))))
	 for (key . original*) = (cond ((symbolp original)
					(cons nil original))
				       ((and (vectorp original)
					     (eq 'remap (aref original 0)))
					(cons original (aref original 1)))
				       (t original))
	 for name
	 = (intern (format "transient-cycles-cmd-%s" (symbol-name original*)))
	 collect
	 `(defun ,name ()
	    ,(format "Like `%s', but augmented with transient cycling."
		     (symbol-name original*))
	    (interactive)
	    (let* (,@bindings
		   (,arg (call-interactively
			  (lambda ,args
			    ,@(if (and (listp (car body))
				       (eq 'interactive (caar body)))
				  body
				(cons (interactive-form original*) body))))))
	      (when-let ((,cycler (funcall ,cycler-generator ,arg))
			 (,tmap (make-sparse-keymap))
			 (,kforwards ,cycle-forwards-key)
			 (,kbackwards ,cycle-backwards-key))
		;; It might be additionally useful to bind something in the
		;; transient map to kill the current buffer and cycle once.
		;;
		;; For the forward direction we could elide this lambda and
		;; just bind the key to the cycler.  But this way means we are
		;; consistent in always supplying an integer.
		(define-key ,tmap ,kforwards (lambda (,arg)
					       (interactive "p")
					       (funcall ,cycler ,arg)))
		(define-key ,tmap ,kbackwards (lambda (,arg)
						(interactive "p")
						(funcall ,cycler (* -1 ,arg))))
		(when transient-cycles-show-cycling-keys
		  (message "Cycle forwards with %s, backwards with %s"
			   (key-description ,kforwards)
			   (key-description ,kbackwards)))
		(set-transient-map ,tmap t ,on-exit))))
	 when key collect `(define-key ,keymap ,key #',name))))
(put 'transient-cycles-define-commands 'common-lisp-indent-function
     '(4 (&whole 2 &rest (&whole 1 4 &body)) &body))

(cl-defmacro transient-cycles-buffer-ring-cycler
    (&key (start 0)
       (ring '(transient-cycles-buffer-siblings-ring ret-val))
       (action '(switch-to-buffer buffer t t)))
  "Yield a lambda expression to cycle RING from START using ACTION.
This macro is intended for use as the CYCLER-GENERATOR argument
to `transient-cycles-define-keys'.

RING is a form which evaluates to a ring of buffers.  It should
be written in terms of `ret-val', which at time of evaluation
will hold the return value of calling the command variant as
described in the docstring of `transient-cycles-define-keys'.
ACTION is a form in terms of `buffer', which should cycle to
`buffer' in the relevant sense."
  (let ((count (gensym))
	(buffers (gensym))
	(buffers-pos (gensym)))
    `(lambda (ret-val)
       (when-let ((,buffers ,ring)
		  (,buffers-pos ,start))
	 (lambda (,count)
	   (interactive "p")
	   (cl-incf ,buffers-pos ,count)
	   (let ((buffer (ring-ref ,buffers ,buffers-pos)))
	     ,action))))))

(defcustom transient-cycles-buffer-siblings-major-modes
  '(("\\`*unsent mail" . message-mode))
  "Alist mapping regexps to major modes.
Buffers whose names match a regexp are considered to have the
associated major mode for the purpose of determining whether they
should be associated with families of clones as generated by
`transient-cycles-buffer-siblings-ring', which see."
  :type '(alist :key-type regexp :value-type symbol)
  :group 'transient-cycles)

(defun transient-cycles-buffer-siblings-ring (buffer)
  "Return ring of BUFFER clones and buffers sharing the clones' major mode.
BUFFER itself is the first element of the ring, followed by the
clones of BUFFER, and then buffers merely sharing the major mode
of the family of clones.

Clonehood is determined by similarity of buffer names.  Clones
produced by `clone-buffer' and `clone-indirect-buffer' will be
counted as siblings, but so will the two Eshell buffers produced
if you type \\[project-eshell] then \\[universal-argument] \\[project-eshell],
as the same naming scheme is used.  This is desirable for
`transient-cycles-buffer-siblings-mode', which see.

The singular major mode of the family of clones is determined
using heuristics, as it is expected that clones of a buffer may
have different major modes: visiting one file with more than one
major mode is one of the primary uses of indirect clones."
  (let* ((clones-hash (make-hash-table))
	 (root-name (buffer-name buffer))
	 (root-name (if (string-match "\\`\\(.+\\)<[0-9]+>\\'" root-name)
			(match-string 1 root-name)
		      root-name))
	 (clones-regexp
	  (concat "\\`" (regexp-quote root-name) "\\(<[0-9]+>\\)?\\'"))
	 (clones-pred
	  (lambda (b) (string-match clones-regexp (buffer-name b))))
	 (buffers (cl-remove-if-not clones-pred (buffer-list)))
	 (mode (or (cdr (assoc root-name
			       transient-cycles-buffer-siblings-major-modes
			       #'string-match))
		   ;; If only one buffer or root clone is visiting a file, use
		   ;; major mode of that one buffer or root clone.  The only
		   ;; case we want here is the root of a family of indirect
		   ;; clones.  Thus, don't consider arbitrary clones visiting
		   ;; files, as this may be because the user cloned, edited
		   ;; down, changed major mode and then wrote to a file.
		   (and (= 1 (length buffers))
			(with-current-buffer (car buffers) major-mode))
		   (let ((root-clone
			  (cl-find root-name buffers
				   :key #'buffer-name :test #'string=)))
		     (and root-clone (with-current-buffer root-clone
				       (and (buffer-file-name) major-mode))))
		   ;; See if the name of one of the clones is a substring of
		   ;; its major mode, and if so, use that mode.
		   ;; E.g. *eww* -> `eww-mode'.  Cases this heuristic will get
		   ;; wrong should have entries in
		   ;; `transient-cycles-buffer-sublings-major-modes'.
		   (cl-loop
		    with root-root-name = (regexp-quote
					   (string-trim root-name "\\*" "\\*"))
		    with case-fold-search = t
		    for buffer in buffers
		    for mode = (symbol-name
				(with-current-buffer buffer major-mode))
		    when (string-match root-root-name mode) return mode)
		   ;; Fallback.
		   (with-current-buffer buffer major-mode))))
    (dolist (buffer buffers) (puthash buffer t clones-hash))
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
	(when (and (eq mode major-mode) (not (gethash buffer clones-hash)))
	  (push buffer buffers))))
    (let ((ring (make-ring (length buffers)))
	  ;; Often BUFFER will be the most recently selected buffer and so the
	  ;; car of the buffer list, but not always, and we always want
	  ;; cycling to begin from BUFFER.
	  (reversed (nreverse (cons buffer (remove buffer buffers)))))
      (dolist (buffer reversed ring) (ring-insert ring buffer)))))


;;;; Minor modes

(defvar transient-cycles-buffer-siblings-mode-map (make-sparse-keymap)
  "Keymap for `transient-cycles-buffer-siblings-mode'.")

(defcustom transient-cycles-buffer-siblings-cycle-backwards-key [left]
  "Key to cycle backwards in the transient maps set by commands
defined by `transient-cycles-buffer-siblings-mode'."
  :type 'key-sequence
  :group 'transient-cycles)

(defcustom transient-cycles-buffer-siblings-cycle-forwards-key [right]
  "Key to cycle forwards in the transient maps set by commands
defined by `transient-cycles-buffer-siblings-mode'."
  :type 'key-sequence
  :group 'transient-cycles)

;;;###autoload
(define-minor-mode transient-cycles-buffer-siblings-mode
    "Enhance buffer switching commands by adding transient cycling.

Augments a number of standard buffer switching commands.  After
typing \\[switch-to-buffer], \\[display-buffer], \\[info] and
some others, you can use the keys
`transient-cycles-buffer-siblings-cycle-backwards-key' and
`transient-cycles-buffer-siblings-cycle-forwards-key' to select a
different, relevantly similar buffer to select or display
instead.  See `transient-cycles-buffer-siblings-ring' for details
of the notion of similarity employed.

The purpose of this mode is to make it easier to handle large
numbers of similarly-named buffers without having to take the
time to manually rename them.  For example, suppose while reading
Info you type \\<Info-mode-map>\\[clone-buffer] several times in
order to view several pieces of information at once.  Later you
need to refer back to one of those buffers, but \\[info] will
always take you to `*info*', and if you use \\[switch-to-buffer]
it might take you several tries to select the buffer you wanted.
Thanks to this minor mode, after using either of those commands
to switch to any `Info-mode' buffer you can quickly cycle through
to the intended target."
  :lighter nil :keymap transient-cycles-buffer-siblings-mode-map :global t
  :group 'transient-cycles)

(transient-cycles-define-commands (prev-buffers)
  (([remap switch-to-buffer] (buffer &optional _norecord force-same-window)
     (prog1 (switch-to-buffer buffer t force-same-window)
       (setq prev-buffers (window-prev-buffers))))

   ([remap switch-to-buffer-other-window] (buffer-or-name &rest _ignore)
     (prog1 (switch-to-buffer-other-window buffer-or-name t)
       (setq prev-buffers (window-prev-buffers))))

   ([remap switch-to-buffer-other-tab] (buffer-or-name)
     (prog1 (window-buffer (switch-to-buffer-other-tab buffer-or-name))
       (setq prev-buffers (window-prev-buffers)))))

  (transient-cycles-buffer-ring-cycler)
  :on-exit (progn (switch-to-buffer (current-buffer) nil t)
		  (set-window-next-buffers nil nil)
		  (set-window-prev-buffers nil prev-buffers))
  :keymap transient-cycles-buffer-siblings-mode-map
  :cycle-forwards-key transient-cycles-buffer-siblings-cycle-forwards-key
  :cycle-backwards-key transient-cycles-buffer-siblings-cycle-backwards-key)

;; Here we don't try to restore the fundamental or frame buffer lists, but it
;; would be possible to do so.  See (info "(elisp) Buffer List").
(transient-cycles-define-commands (window prev-buffers)
  (([remap display-buffer] (buffer-or-name &optional action frame)
     (prog1 (setq window (display-buffer buffer-or-name action frame))
       (setq prev-buffers (window-prev-buffers window))))

   ([remap info] (&optional file-or-node buffer)
    (prog2 (info file-or-node buffer)
	(setq window (get-buffer-window buffer))
      (setq prev-buffers (and window (window-prev-buffers window))))))

  (transient-cycles-buffer-ring-cycler
   :ring (transient-cycles-buffer-siblings-ring (window-buffer ret-val))
   :action
   (with-selected-window ret-val
     (let ((display-buffer-overriding-action
	    '((display-buffer-same-window) (inhibit-same-window . nil))))
       (display-buffer buffer))))
  :on-exit (progn (set-window-next-buffers window nil)
		  (set-window-prev-buffers window prev-buffers))
  :keymap transient-cycles-buffer-siblings-mode-map
  :cycle-forwards-key transient-cycles-buffer-siblings-cycle-forwards-key
  :cycle-backwards-key transient-cycles-buffer-siblings-cycle-backwards-key)

(defvar transient-cycles-window-buffers-mode-map (make-sparse-keymap)
  "Keymap for `transient-cycles-window-buffers-mode'.")

(defcustom transient-cycles-window-buffers-cycle-backwards-key [left]
  "Key to cycle backwards in the transient maps set by commands
defined by `transient-cycles-window-buffers-mode'."
  :type 'key-sequence
  :group 'transient-cycles)

(defcustom transient-cycles-window-buffers-cycle-forwards-key [right]
  "Key to cycle forwards in the transient maps set by commands
defined by `transient-cycles-window-buffers-mode'."
  :type 'key-sequence
  :group 'transient-cycles)

;;;###autoload
(define-minor-mode transient-cycles-window-buffers-mode
    "Enhance window buffer switching commands by adding transient cycling.

Augments \\[previous-buffer] and \\[next-buffer].  After typing
those commands, you can use
`transient-cycles-window-buffers-cycle-backwards-key' and
`transient-cycles-window-buffers-cycle-forwards-key' to move
forwards and backwards in a virtual list of the window's
previous, current and next buffers.  When transient cycling
completes, your starting point will be stored, such that
\\[transient-cycles-window-buffers-back-and-forth] can quickly
take you back there."
  :lighter nil :keymap transient-cycles-window-buffers-mode-map :global t
  :group 'transient-cycles
  (if transient-cycles-window-buffers-mode
      ;; Clear window parameter just when the list of next buffers is cleared.
      (advice-add 'set-window-buffer :after
		  #'transient-cycles--reset-window-recent-buffer)
    (advice-remove 'set-window-buffer
		   #'transient-cycles--reset-window-recent-buffer)))

(cl-symbol-macrolet
    ((param (window-parameter nil 'transient-cycles--window-recent-buffer)))
  (transient-cycles-define-commands (recent-buffer last-recent-buffer)
    (([remap previous-buffer] (count)
       (interactive "p")
       (setq recent-buffer (and (window-next-buffers) count)
	     last-recent-buffer param)
       (previous-buffer count))

     ([remap next-buffer] (count)
       (interactive "p")
       ;; We consider only the window's next buffers, not the frame's next
       ;; buffers as `next-buffer' does.  This is because otherwise our
       ;; `recent-buffer' and window parameter become invalid.
       ;;
       ;; `previous-buffer' and `next-buffer' use `switch-to-prev-buffer' and
       ;; `switch-to-next-buffer' as subroutines, so buffers previously shown
       ;; in the selected window come up first
       (if (window-next-buffers)
	   (progn (setq recent-buffer (* -1 count)
			last-recent-buffer param)
		  (next-buffer count))
	 (user-error "No next buffer"))))

    (lambda (_ignore)
      (lambda (count)
	(if (cl-plusp count)
	    (if (window-next-buffers)
		(progn (when recent-buffer (cl-decf recent-buffer count))
		       (next-buffer count))
	      (message "No next buffer"))
	  (setq count (* -1 count))
	  (when recent-buffer (cl-incf recent-buffer count))
	  (previous-buffer count))))
    ;; If `recent-buffer' is zero then we are back where we started.
    ;; in.  In that case, restore the old parameter value so that
    ;; `transient-cycles-window-buffers-back-and-forth' does something useful.
    :on-exit (setq param (if (and recent-buffer (zerop recent-buffer))
			     last-recent-buffer
			   recent-buffer))
    :keymap transient-cycles-window-buffers-mode-map
    :cycle-forwards-key transient-cycles-window-buffers-cycle-forwards-key
    :cycle-backwards-key transient-cycles-window-buffers-cycle-backwards-key))

(defun transient-cycles--reset-window-recent-buffer (&rest _ignore)
  (set-window-parameter nil 'transient-cycles--window-recent-buffer nil))

(defun transient-cycles-window-buffers-back-and-forth ()
  "Switch to the buffer most recently accessed using the bindings
established by `transient-cycles-window-buffers-mode', on the
condition that no other commands have set this window's buffer
since then.  Otherwise, call `previous-buffer'."
  (interactive)
  (cl-symbol-macrolet
      ((param (window-parameter nil 'transient-cycles--window-recent-buffer)))
    (cond (param
	   (let ((new (and (window-next-buffers) (* -1 param))))
	     (cond ((cl-plusp param) (next-buffer param))
		   ((cl-minusp param) (previous-buffer (* -1 param))))
	     (setq param new)))
	  ((window-next-buffers)
	   (let ((count (length (window-next-buffers))))
	     (next-buffer count)
	     (setq param (* -1 count))))
	  (t (previous-buffer)))))

(defvar transient-cycles-tab-bar-mode-map (make-sparse-keymap)
  "Keymap for `transient-cycles-tab-bar-mode'.")

;;;###autoload
(define-minor-mode transient-cycles-tab-bar-mode
    "Enhance tab switching commands by adding transient cycling.

Augments \\[tab-previous], \\[tab-next] and
\\[tab-bar-switch-to-recent-tab].  After running those commands,
you can use `transient-cycles-tab-bar-cycle-backwards-key' and
`transient-cycles-tab-bar-cycle-forwards-key' to move forwards
and backwards in the list of tabs.  When transient cycling
completes, tab access times will be as though you had moved
directly from the first tab to the final tab.  That means that
\\[tab-bar-switch-to-recent-tab] may be used to switch back and
forth between the first tab and the final tab."
  :lighter nil :keymap transient-cycles-tab-bar-mode-map :global t
  :group 'transient-cycles)

(defcustom transient-cycles-tab-bar-cycle-backwards-key [left]
  "Key to cycle backwards in the transient maps set by commands
defined by `transient-cycles-tab-bar-mode'."
  :type 'key-sequence
  :group 'transient-cycles)

(defcustom transient-cycles-tab-bar-cycle-forwards-key [right]
  "Key to cycle forwards in the transient maps set by commands
defined by `transient-cycles-tab-bar-mode'."
  :type 'key-sequence
  :group 'transient-cycles)

(transient-cycles-define-commands (recent-tab-old-time)
  (([remap tab-previous] (count)
     (setq recent-tab-old-time (transient-cycles--nth-tab-time (* -1 count)))
     (tab-previous count))

   ;; `tab-bar-switch-to-recent-tab' does not have a binding by default but
   ;; establish a remapping so that the user can easily access the transient
   ;; cycling variant simply by adding a binding for the original command.
   ([remap tab-bar-switch-to-recent-tab] (count)
     (setq recent-tab-old-time
	   (cl-loop for tab in (funcall tab-bar-tabs-function)
		 unless (eq 'current-tab (car tab))
		 minimize (cdr (assq 'time tab))))
     (tab-bar-switch-to-recent-tab count))

   ([remap tab-next] (count)
     (setq recent-tab-old-time (transient-cycles--nth-tab-time count))
     (tab-next count)))

  (lambda (_ignore)
    (lambda (count)
      ;; We are moving away from the current tab, so restore its time as if
      ;; we had never selected it, and store the time of the tab we're
      ;; moving to in case we need to do this again.
      (let ((next-tab-old-time (transient-cycles--nth-tab-time count)))
	(tab-bar-switch-to-next-tab count)
	(cl-loop with max
	      for tab in (funcall tab-bar-tabs-function)
	      for tab-time = (assq 'time tab)
	      when (and (not (eq 'current-tab (car tab)))
			(or (not max) (> (cdr tab-time) (cdr max))))
	      do (setq max tab-time)
	      finally (setcdr max recent-tab-old-time))
	(setq recent-tab-old-time next-tab-old-time))))
  :keymap transient-cycles-tab-bar-mode-map
  :cycle-forwards-key transient-cycles-tab-bar-cycle-forwards-key
  :cycle-backwards-key transient-cycles-tab-bar-cycle-backwards-key)

(defun transient-cycles--nth-tab-time (n)
  (let* ((tabs (funcall tab-bar-tabs-function))
	 (current-index (cl-position 'current-tab tabs :key #'car))
	 (new-index (mod (+ n current-index) (length tabs))))
    (alist-get 'time (nth new-index tabs))))

(provide 'transient-cycles)

;;; transient-cycles.el ends here

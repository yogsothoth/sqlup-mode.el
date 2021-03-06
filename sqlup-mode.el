;;; sqlup-mode.el --- Upcase SQL words for you

;; Copyright (C) 2014 Aldric Giacomoni

;; Author: Aldric Giacomoni <trevoke@gmail.com>
;; URL: https://github.com/trevoke/sqlup-mode.el
;; Created: Jun 25 2014
;; Version: 0.5.9
;; Keywords: sql, tools

;;; License:

;; This file is not part of GNU Emacs

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; `M-x sqlup-mode` and just type.
;; This mode supports the various built-in SQL modes as well as redis-mode.
;; The capitalization is triggered when you press the following keys:
;; * SPC
;; * RET
;; * ,
;; * ;
;; * (
;; * '
;;
;; This package also provides a function to capitalize SQL keywords inside a region - always available, no need to activate the minor mode to use it:
;;
;; M-x sqlup-capitalize-keywords-in-region
;;
;; It is not bound to a keybinding. Here is an example of how you could do it:
;;
;; (global-set-key (kbd "C-c u") 'sqlup-capitalize-keywords-in-region)
;;
;; Here follows an example setup to activate `sqlup-mode` automatically:
;;
;; (add-hook 'sql-mode-hook 'sqlup-mode)
;; (add-hook 'sql-interactive-mode-hook 'sqlup-mode)
;; (add-hook 'redis-mode-hook 'sqlup-mode)



;;; Code:

(require 'cl)

(defconst sqlup-trigger-characters
  (mapcar 'string-to-char '(";"
                           " "
                           "("
                           ","
                           "''"))
  "When the user types one of these characters,
this mode's logic will be evaluated.")

(defconst sqlup-eval-keywords
  '((postgres "EXECUTE" "format("))
  "List of keywords introducing eval strings, organised by dialect.")

(defvar sqlup-local-keywords nil
    "Buffer local variable holding regexps to identify keywords.")

;;;###autoload
(define-minor-mode sqlup-mode
  "Capitalizes SQL keywords for you."
  :lighter " SUP"
  (if sqlup-mode
      (sqlup-enable-keyword-capitalization)
    (sqlup-disable-keyword-capitalization)))

(defun sqlup-enable-keyword-capitalization ()
  "Add buffer-local hook to handle this mode's logic"
  (set (make-local-variable 'sqlup-local-keywords) nil)
  (set (make-local-variable 'sqlup-last-sql-keyword) nil)
  (add-hook 'post-command-hook 'sqlup-capitalize-as-you-type nil t))

(defun sqlup-disable-keyword-capitalization ()
  "Remove buffer-local hook to handle this mode's logic"
  (remove-hook 'post-command-hook 'sqlup-capitalize-as-you-type t))

(defun sqlup-capitalize-as-you-type ()
  "This function is the post-command hook. This code gets run after every command in a buffer with this minor mode enabled."
  (if (sqlup-should-do-work-p)
      (save-excursion (sqlup-maybe-capitalize-symbol -1))))

(defun sqlup-should-do-work-p ()
  "Sqlup is triggered after user keypresses. Here we check that this was one of the keypresses we care about."
  (or (sqlup-user-pressed-return-p)
      (and (sqlup-user-is-typing-p)
           (sqlup-trigger-self-insert-character-p))))

(defun sqlup-user-pressed-return-p ()
  (and (< 0 (length (this-command-keys-vector)))
       (or (equal 13 (elt (this-command-keys-vector) 0))
           (equal 10 (elt (this-command-keys-vector) 0)))))

(defun sqlup-user-is-typing-p ()
  (eq this-command #'self-insert-command))

(defun sqlup-trigger-self-insert-character-p ()
  (let ((sqlup-current-char (elt (this-command-keys-vector) 0)))
    (member sqlup-current-char sqlup-trigger-characters)))

(defun sqlup-maybe-capitalize-symbol (direction)
  "DIRECTION is either 1 for forward or -1 for backward"
  (forward-symbol direction)
  (sqlup-work-on-symbol (thing-at-point 'symbol)
                        (bounds-of-thing-at-point 'symbol)))

(defun sqlup-work-on-symbol (symbol symbol-boundaries)
  (if (and symbol
           (sqlup-keyword-p (downcase symbol))
           (sqlup-capitalizable-p (point)))
      (progn
        (upcase-region (car symbol-boundaries)
                       (cdr symbol-boundaries)))))

(defun sqlup-match-eval-keyword-p (dialect)
  "Return t if the code just before point ends with an eval keyword valid in DIALECT."
  (some 'identity
        (mapcar #'(lambda (kw) (looking-back (concat kw "[\s\n\r\t]*")))
                (cdr (assoc dialect sqlup-eval-keywords)))))

(defun sqlup-in-eval-string-p (dialect)
  "Return t if we are in an eval string."
  (save-excursion
    (if (sqlup-string-p)
        (progn
          (goto-char (nth 8 (syntax-ppss)))
          (sqlup-match-eval-keyword-p dialect)))))

(defun sqlup-capitalizable-p (point-location)
  (let ((old-buffer (current-buffer))
        (dialect (or (and (boundp 'sql-product) sql-product) 'ansi)))
    (with-temp-buffer
      (insert-buffer-substring old-buffer)
      (sql-mode)
      (goto-char point-location)
      (and (not (sqlup-comment-p))
           (not (and (not (sqlup-in-eval-string-p dialect))
                     (sqlup-string-p)))))))

(defun sqlup-comment-p ()
  (and (nth 4 (syntax-ppss)) t))

(defun sqlup-string-p ()
  (and (nth 3 (syntax-ppss)) t))

;;;###autoload
(defun sqlup-capitalize-keywords-in-region (start-pos end-pos)
  "Call this function on a region to capitalize the SQL keywords therein."
  (interactive "r")
  (save-excursion
    (goto-char start-pos)
    (while (< (point) end-pos)
      (sqlup-maybe-capitalize-symbol 1))))

(defun sqlup-keywords-regexps ()
  (if (not sqlup-local-keywords)
      (set (make-local-variable 'sqlup-local-keywords) (sqlup-find-correct-keywords)))
  sqlup-local-keywords)

(defun sqlup-find-correct-keywords ()
  """Depending on the major mode (redis-mode or sql-mode), find the
correct keywords. If not, create a (hopefully sane) default based on
ANSI SQL keywords.
"""
(cond ((sqlup-redis-mode-p) (mapcar 'downcase redis-keywords))
      ((sqlup-within-sql-buffer-p) (mapcar 'car sql-mode-font-lock-keywords))
      (t (mapcar 'car (sql-add-product-keywords
                       (sqlup-valid-sql-product) '())))))

(defun sqlup-valid-sql-product ()
  (or (and (boundp 'sql-product)
           sql-product)
      'ansi))

(defun sqlup-redis-mode-p ()
  (eq major-mode #'redis-mode))

(defun sqlup-within-sql-buffer-p ()
  (and (boundp 'sql-mode-font-lock-keywords) sql-mode-font-lock-keywords))

(defun sqlup-keyword-p (word)
  (let* ((sqlup-keyword-found nil)
         (sqlup-terms (sqlup-keywords-regexps))
         (sqlup-term (car sqlup-terms))
         (temp-syntax (make-syntax-table)))
    (modify-syntax-entry ?_ "w" temp-syntax)
    (with-syntax-table temp-syntax
      (while (and (not sqlup-keyword-found)
                  sqlup-terms)
        (setq sqlup-keyword-found (string-match sqlup-term word))
        (setq sqlup-term (car sqlup-terms))
        (setq sqlup-terms (cdr sqlup-terms)))
      (and sqlup-keyword-found t))))

;; Advice sql-set-product, to invalidate sqlup's keyword cache after changing
;; the sql product. We need to advice sql-set-product since sql-mode does not
;; provide any hook that runs after changing the product
(defadvice sql-set-product (after sqlup-invalidate-sqlup-keyword-cache activate)
  "Invalidate sqlup-keyword cache after sql-product changes"
  (setq sqlup-local-keywords nil))

(provide 'sqlup-mode)
;;; sqlup-mode.el ends here

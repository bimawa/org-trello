;;; org-trello.el --- Minor mode to synchronize org-mode buffer and trello board

;; Copyright (C) 2013 Antoine R. Dumont <eniotna.t AT gmail.com>

;; Author: Antoine R. Dumont <eniotna.t AT gmail.com>
;; Maintainer: Antoine R. Dumont <eniotna.t AT gmail.com>
;; Version: 0.7.4
;; Package-Requires: ((emacs "24") (dash "2.11.0") (dash-functional "2.11.0") (s "1.9.0") (deferred "0.3.2") (request-deferred "0.2.0"))
;; Keywords: org-mode trello sync org-trello
;; URL: https://github.com/org-trello/org-trello

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING. If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; Minor mode to sync org-mode buffer and trello board
;;
;; 1) Add the following to your Emacs init file
;; - Either activate org-trello-mode in an org-buffer - M-x org-trello-mode
;;
;; - Or add this in your Emacs setup
;; (require 'org-trello)
;; (add-hook 'org-mode-hook 'org-trello-mode)
;;
;; 2) Once - Install the consumer-key and read/write access-token for org-trello
;; to work in your name with your boards (C-c o i) or
;; M-x org-trello-install-key-and-token
;; (See http://org-trello.github.io/trello-setup.html#credentials for more
;; details)
;;
;; You may want:
;; - to connect your org buffer to an existing board (C-c o I).  Beware that
;; this will only install properties needed to speak with trello board (and
;; nothing else).
;; M-x org-trello-install-board-metadata
;;
;; - to update an existing org-buffer connected to a trello board (C-c o u).
;; M-x org-trello-update-board-metadata
;;
;; - to create an empty board directly from a org-mode buffer (C-c o b)
;; M-x org-trello-create-board-and-install-metadata
;;
;; 3) Now check your setup is ok (C-c o d)
;; M-x org-trello-check-setup
;;
;; 6) For some more help (C-c o h)
;; M-x org-trello-help-describing-setup
;;
;; 7) The first time you attached your buffer to an existing trello board, you
;; may want to bootstrap your org-buffer (C-u C-c o s)
;; C-u M-x org-trello-sync-buffer
;;
;; 8) Sync a card from Org to Trello (C-c o c / C-c o C)
;; M-x org-trello-sync-card
;;
;; 9) Sync a card from Trello to Org (C-u C-c o c / C-u C-c o C)
;; C-u M-x org-trello-sync-card
;;
;; 10) Sync complete org buffer to trello (C-c o s)
;; M-x org-trello-sync-buffer
;;
;; 11) As already mentioned, you can sync all the org buffer from trello
;; (C-u C-c o s) or C-u M-x org-trello-sync-buffer
;;
;; 12) You can delete an entity, card/checklist/item at point (C-c o k)
;; M-x org-trello-kill-entity
;;
;; 13) You can delete all the cards (C-c o K / C-u C-c o k)
;; M-x org-trello-kill-cards / C-u M-x org-trello-kill-entity
;;
;; 14) You can directly jump to the trello card in the browser (C-c o j)
;; M-x org-trello-jump-to-trello-card
;;
;; 15) You can directly jump to the trello board in the browser
;; (C-c o J / C-u C-c o j)
;; M-x org-trello-jump-to-trello-board / C-u M-x org-trello-jump-to-trello-card
;;
;; Now you can work with trello from the comfort of org-mode and Emacs
;;
;; Enjoy!
;;
;; More informations: https://org-trello.github.io
;; Issue tracker: https://github.com/org-trello/org-trello-issues

;;; Code:

(defconst org-trello-error-install-msg
  (format "Oops - your Emacs isn't supported.
`org-trello' only works on Emacs 24.3+ and you're running version: %s.
Please consider upgrading Emacs." emacs-version)
  "Error message when installing org-trello with an unsupported Emacs version.")

(when (version< emacs-version "24") (error org-trello-error-install-msg))

;; Dependency on internal Emacs libs
(require 'org)
(require 'json)
(require 'parse-time)

(defconst org-trello--version "0.7.4" "Current org-trello version installed.")



(require 'org-trello-utils)
(require 'org-trello-log)
(require 'org-trello-setup)
(require 'org-trello-action)
(require 'org-trello-controller)
(require 'org-trello-buffer)



;;;###autoload
(defun org-trello-version ()
  "Org-trello version."
  (interactive)
  (orgtrello-log-msg orgtrello-log-no-log "version: %s" org-trello--version))

(defalias 'org-trello/version 'org-trello-version)



(defun org-trello-apply-deferred (computation)
  "Apply the deferred COMPUTATION."
  (with-current-buffer (current-buffer)
    (save-excursion
      (apply (car computation) (cdr computation)))))

(defun org-trello-apply (comp &optional current-buffer-to-save nolog-p)
  "Apply org-trello computation COMP.
When CURRENT-BUFFER-TO-SAVE (buffer name) is provided, save such buffer.
when NOLOG-P is specified, no output log."
  (lexical-let ((computation        comp)
                (prefix-log-message (cadr comp))
                (buffer-to-save     current-buffer-to-save)
                (nolog-flag         nolog-p))
    (deferred:$
      (deferred:next (lambda () (save-excursion
                             (with-local-quit
                               (apply (car computation) (cdr computation))))))
      (deferred:nextc it
        (lambda ()
          (when buffer-to-save
            (orgtrello-buffer-save-buffer buffer-to-save))
          (unless nolog-flag
            (orgtrello-log-msg orgtrello-log-info
                               "%s - Done!"
                               prefix-log-message))))
      (deferred:error it
        (-partial
         #'orgtrello-log-msg
         orgtrello-log-error
         "Main apply function - Problem during execution - '%s'!")))))

(defun org-trello-log-strict-checks-and-do (action-label
                                            action-fn
                                            &optional with-save-flag)
  "Given an ACTION-LABEL and an ACTION-FN, execute sync action.
If WITH-SAVE-FLAG is set, will do a buffer save and reload the org setup."
  (orgtrello-action-msg-controls-or-actions-then-do
   action-label
   '(orgtrello-controller-migrate-user-setup
     orgtrello-controller-set-account
     orgtrello-controller-load-keys
     orgtrello-controller-control-keys
     orgtrello-controller-setup-properties
     orgtrello-controller-control-properties)
   action-fn))

(defun org-trello-log-light-checks-and-do (action-label
                                           action-fn
                                           &optional no-check-flag)
  "Given an ACTION-LABEL and an ACTION-FN, execute sync action.
If NO-CHECK-FLAG is set, no controls are done."
  (orgtrello-action-msg-controls-or-actions-then-do
   action-label
   (if no-check-flag nil '(orgtrello-controller-migrate-user-setup
                           orgtrello-controller-set-account
                           orgtrello-controller-load-keys
                           orgtrello-controller-control-keys
                           orgtrello-controller-setup-properties))
   action-fn))

;;;###autoload
(defun org-trello-abort-sync ()
  "Control first, then if ok, add a comment to the current card."
  (interactive)
  (deferred:clear-queue)
  (orgtrello-log-msg orgtrello-log-info "Cancel actions done!"))

(defalias 'org-trello/abort-sync 'org-trello-abort-sync)

;;;###autoload
(defun org-trello-add-card-comment (&optional from)
  "Control first, then if ok, add a comment to the current card.
When FROM is set, this will delete the current card's comments."
  (interactive "P")
  (org-trello-apply (cons 'org-trello-log-strict-checks-and-do
                          (if from
                              '("Remove current comment at point"
                                orgtrello-controller-do-delete-card-comment)
                            '("Add card comment"
                              orgtrello-controller-do-add-card-comment)))))

(defalias 'org-trello/add-card-comment 'org-trello-add-card-comment)

;;;###autoload
(defun org-trello-delete-card-comment ()
  "Control first, then if ok, delete the comment at point.
This will only work if you are the owner of the comment."
  (interactive)
  (org-trello-apply-deferred '(org-trello-log-strict-checks-and-do
                               "Remove current comment at point"
                               orgtrello-controller-do-delete-card-comment)))

(defalias 'org-trello/delete-card-comment 'org-trello-delete-card-comment)

;;;###autoload
(defun org-trello-show-board-labels ()
  "Control, then if ok, show a simple buffer with the current board's labels."
  (interactive)
  (org-trello-apply '(org-trello-log-strict-checks-and-do
                      "Display current board's labels"
                      orgtrello-controller-do-show-board-labels)))

(defalias 'org-trello/show-board-labels 'org-trello-show-board-labels)

;;;###autoload
(defun org-trello-sync-card (&optional from)
  "Execute the sync of an entity and its structure to trello.
If FROM is non nil, execute the sync entity and its structure from trello."
  (interactive "P")
  (org-trello-apply-deferred
   (cons 'org-trello-log-strict-checks-and-do
         (if from
             '("Request 'sync entity with structure from trello"
               orgtrello-controller-checks-then-sync-card-from-trello)
           '("Request 'sync entity with structure to trello"
             orgtrello-controller-checks-then-sync-card-to-trello)))))

(defalias 'org-trello/sync-card 'org-trello-sync-card)

;;;###autoload
(defun org-trello-sync-comment (&optional from)
  "Execute the sync of the card's comment at point.
If FROM is non nil, remove the comment at point."
  (interactive "P")
  (org-trello-apply-deferred
   (cons 'org-trello-log-strict-checks-and-do
         (if from
             '("Remove current comment at point"
               orgtrello-controller-do-delete-card-comment)
           '("Sync comment to trello"
             orgtrello-controller-do-sync-card-comment)))))

(defalias 'org-trello/sync-comment 'org-trello-sync-comment)

;;;###autoload
(defun org-trello-sync-buffer (&optional from)
  "Execute the sync of the entire buffer to trello.
If FROM is non nil, execute the sync of the entire buffer from trello."
  (interactive "P")
  (org-trello-apply-deferred
   (cons 'org-trello-log-strict-checks-and-do
         (if from
             '("Request 'sync org buffer from trello board'"
               orgtrello-controller-do-sync-buffer-from-trello)
           '("Request 'sync org buffer to trello board'"
             orgtrello-controller-do-sync-buffer-to-trello)))))

(defalias 'org-trello/sync-buffer 'org-trello-sync-buffer)

;;;###autoload
(defun org-trello-kill-entity (&optional from)
  "Execute the entity removal from trello and the buffer.
If FROM is non nil, execute all entities removal from trello and buffer."
  (interactive "P")
  (org-trello-apply-deferred
   (cons 'org-trello-log-strict-checks-and-do
         (if from
             '("Delete all cards" orgtrello-controller-do-delete-entities)
           '("Delete entity at point (card/checklist/item)"
             orgtrello-controller-checks-then-delete-simple)))))

(defalias 'org-trello/kill-entity 'org-trello-kill-entity)

;;;###autoload
(defun org-trello-kill-cards ()
  "Execute all entities removal from trello and buffer."
  (interactive)
  (org-trello-apply-deferred '(org-trello-log-strict-checks-and-do
                               "Delete Cards"
                               orgtrello-controller-do-delete-entities)))

(defalias 'org-trello/kill-cards 'org-trello-kill-cards)

;;;###autoload
(defun org-trello-archive-card ()
  "Execute archive card at point."
  (interactive)
  (org-trello-apply-deferred '(org-trello-log-strict-checks-and-do
                               "Archive Card at point"
                               orgtrello-controller-checks-and-do-archive-card)))

(defalias 'org-trello/archive-card 'org-trello-archive-card)

;;;###autoload
(defun org-trello-archive-cards ()
  "Execute archive all the DONE cards from buffer."
  (interactive)
  (org-map-entries 'org-trello-archive-card "/DONE" 'file))

(defalias 'org-trello/archive-cards 'org-trello-archive-cards)

;;;###autoload
(defun org-trello-install-key-and-token ()
  "No control, trigger setup installation of key and read/write token."
  (interactive)
  (orgtrello-controller-do-install-key-and-token))

(defalias 'org-trello/install-key-and-token 'org-trello-install-key-and-token)

;;;###autoload
(defun org-trello-install-board-metadata ()
  "Control, if ok, trigger setup installation of trello board to sync with."
  (interactive)
  (org-trello-apply-deferred
   '(org-trello-log-light-checks-and-do
     "Install boards and lists"
     orgtrello-controller-do-install-board-and-lists)))

(defalias 'org-trello/install-board-metadata 'org-trello-install-board-metadata)

;;;###autoload
(defun org-trello-update-board-metadata ()
  "Control first, then if ok, trigger the update of the informations about the board."
  (interactive)
  (org-trello-apply-deferred '(org-trello-log-light-checks-and-do
                               "Update board information"
                               orgtrello-controller-do-update-board-metadata)))

(defalias 'org-trello/update-board-metadata 'org-trello-update-board-metadata)

;;;###autoload
(defun org-trello-jump-to-trello-card (&optional from)
  "Jump from current card to trello card in browser.
If FROM is not nil, jump from current card to board."
  (interactive "P")
  (org-trello-apply
   (cons 'org-trello-log-strict-checks-and-do
         (if from
             '("Jump to board" orgtrello-controller-jump-to-board)
           '("Jump to card" orgtrello-controller-jump-to-card)))))

(defalias 'org-trello/jump-to-trello-card 'org-trello-jump-to-trello-card)

;;;###autoload
(defun org-trello-jump-to-trello-board ()
  "Jump to current trello board."
  (interactive)
  (org-trello-apply '(org-trello-log-strict-checks-and-do
                      "Jump to board"
                      orgtrello-controller-jump-to-board)))

(defalias 'org-trello/jump-to-trello-board 'org-trello-jump-to-trello-board)

;;;###autoload
(defun org-trello-create-board-and-install-metadata ()
  "Control first, then if ok, trigger the board creation."
  (interactive)
  (org-trello-apply-deferred
   '(org-trello-log-light-checks-and-do
     "Create board and lists"
     orgtrello-controller-do-create-board-and-install-metadata)))

(defalias 'org-trello/create-board-and-install-metadata
  'org-trello-create-board-and-install-metadata)

;;;###autoload
(defun org-trello-assign-me (&optional unassign)
  "Assign oneself to the card.
If UNASSIGN is not nil, unassign oneself from the card."
  (interactive "P")
  (org-trello-apply (cons 'org-trello-log-light-checks-and-do
                          (if unassign
                              '("Unassign me from card"
                                orgtrello-controller-do-unassign-me)
                            '("Assign myself to card"
                              orgtrello-controller-do-assign-me)))
                    (current-buffer)))

(defalias 'org-trello/assign-me 'org-trello-assign-me)

;;;###autoload
(defun org-trello-check-setup ()
  "Check the current setup."
  (interactive)
  (org-trello-apply '(org-trello-log-strict-checks-and-do
                      "Checking setup."
                      orgtrello-controller-check-trello-connection)
                    nil 'no-log))

(defalias 'org-trello/check-setup 'org-trello-check-setup)

;;;###autoload
(defun org-trello-delete-setup ()
  "Delete the current setup."
  (interactive)
  (org-trello-apply '(org-trello-log-strict-checks-and-do
                      "Delete current org-trello setup"
                      orgtrello-controller-delete-setup)
                    (current-buffer)))

(defalias 'org-trello/delete-setup 'org-trello-delete-setup)

;;;###autoload
(defun org-trello-help-describing-bindings ()
  "A simple message to describe the standard bindings used."
  (interactive)
  (org-trello-apply
   `(message ,(orgtrello-setup-help-describing-bindings-template
               org-trello-current-prefix-keybinding
               org-trello-interactive-command-binding-couples))
   nil
   nil
   'no-log))

(defalias 'org-trello/help-describing-bindings
  'org-trello-help-describing-bindings)

(defun org-trello--bug-report ()
  "Compute the bug report for the user to include."
  (->> `("Please:"
         "- Describe your problem with clarity and conciceness (cf. https://www.gnu.org/software/emacs/manual/html_node/emacs/Understanding-Bug-Reporting.html)"
         "- Explicit your installation choice (melpa, marmalade, el-get, tarball, git clone...)."
         "- Activate `'trace`' in logs for more thorough output in *Message* buffer: (custom-set-variables '(orgtrello-log-level orgtrello-log-trace))."
         "- A scrambled sample (of the user's and board's ids) of your org-trello buffer with problems."
         "- Report the following message trace inside your issue."
         ""
         "System information:"
         ,(format "- system-type: %s" system-type)
         ,(format "- locale-coding-system: %s" locale-coding-system)
         ,(format "- emacs-version: %s" (emacs-version))
         ,(format "- org version: %s" (org-version))
         ,(format "- org-trello version: %s" org-trello--version)
         ,(format "- org-trello path: %s" (find-library-name "org-trello")))
       (s-join "\n")))

(defun org-trello-bug-report (&optional open-url)
  "Display a bug report message.
When OPEN-URL is filled, with universal argument (`C-u') is used,
opens new issue in org-trello's github tracker."
  (interactive "P")
  (when open-url
    (browse-url "https://github.com/org-trello/org-trello-issues/new"))
  (orgtrello-log-msg orgtrello-log-info (org-trello--bug-report)))



;;;###autoload
(define-minor-mode org-trello-mode
  "Sync your org-mode and your trello together."
  :lighter " ot"
  :keymap org-trello-mode-map
  :group 'org-trello)

(defcustom org-trello-mode-hook nil
  "Define org-trello hook for user to extend mode with their own behavior."
  :type 'hook
  :group 'org-trello)

(setq org-trello-mode-on-hook) ;; for dev
(add-hook 'org-trello-mode-on-hook 'orgtrello-controller-mode-on-hook-fn)

(add-hook 'org-trello-mode-on-hook
          (lambda ()
            ;; install the bindings
            (orgtrello-setup-install-local-prefix-mode-keybinding
             (if (boundp 'org-trello-current-prefix-keybinding)
                 org-trello-current-prefix-keybinding
               org-trello-default-prefix-keybinding))
            ;; Overwrite the org-mode-map
            (define-key org-trello-mode-map [remap org-end-of-line]
              'orgtrello-buffer-end-of-line)
            (define-key org-trello-mode-map [remap org-return]
              'orgtrello-buffer-org-return)
            (define-key org-trello-mode-map [remap org-ctrl-c-ret]
              'orgtrello-buffer-org-ctrl-c-ret)
            (define-key org-trello-mode-map [remap org-archive-subtree]
              'org-trello-archive-card)
            ;; a little message in the minibuffer to notify the user
            (orgtrello-log-msg orgtrello-log-no-log
                               (orgtrello-setup-startup-message
                                org-trello-current-prefix-keybinding)))
          'do-append)

(setq org-trello-mode-off-hook) ;; for dev
(add-hook 'org-trello-mode-off-hook 'orgtrello-controller-mode-off-hook-fn)

(add-hook 'org-trello-mode-off-hook
          (lambda ()
            ;; remove the bindings when org-trello mode off
            (orgtrello-setup-remove-local-prefix-mode-keybinding
             (if (boundp 'org-trello-current-prefix-keybinding)
                 org-trello-current-prefix-keybinding
               org-trello-default-prefix-keybinding))
            ;; remove mapping override
            (define-key org-trello-mode-map [remap org-end-of-line] nil)
            (define-key org-trello-mode-map [remap org-return] nil)
            (define-key org-trello-mode-map [remap org-ctrl-c-ret] nil)
            (define-key org-trello-mode-map [remap org-archive-subtree] nil)
            ;; a little message in the minibuffer to notify the user
            (orgtrello-log-msg orgtrello-log-no-log "Wish you well, master."))
          'do-append)

(defcustom org-trello-files nil
  "Org-trello files that needs org-trello activated when opened."
  :type 'list
  :require 'org-trello
  :group 'org-trello)

(add-hook 'org-mode-hook
          (lambda ()
            (when (-any? (lambda (name)
                           (string= (expand-file-name name) buffer-file-name))
                         org-trello-files)
              (org-trello-mode))))

(orgtrello-log-msg orgtrello-log-debug "org-trello loaded!")

(provide 'org-trello)
;;; org-trello.el ends here

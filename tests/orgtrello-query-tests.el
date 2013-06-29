(require 'orgtrello-query)

(ert-deftest testing-orgtrello--compute-method ()
  (should (equal (orgtrello--compute-method :get)    "GET"))
  (should (equal (orgtrello--compute-method :post)   "POST"))
  (should (equal (orgtrello--compute-method :put)    "PUT"))
  (should (equal (orgtrello--compute-method :delete) "DELETE")))

(ert-deftest testing-orgtrello--compute-url ()
  (should (equal (orgtrello--compute-url "/uri")
                 (format "%s%s" *TRELLO-URL* "/uri")))
  (should (equal (orgtrello--compute-url "/uri/other")
                 (format "%s%s" *TRELLO-URL* "/uri/other")))
  (should (equal (orgtrello--compute-url "/uri/some/other")
                 (format "%s%s" *TRELLO-URL* "/uri/some/other"))))

(provide 'orgtrello-query-tests)

;;; orgtrello-query-tests.el end here
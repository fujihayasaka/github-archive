class Zuorest::Model::Account < Zuorest::Model::Base
  zuora_rest_namespace "/v1/accounts/", url_template: "/v1/accounts/:id"

  has_many :invoices, 
    rest_namespace: "/v1/transactions/invoices/accounts/",
    url_template: "/v1/transactions/invoices/accounts/:id"
    
  has_many :invoices_new, 
    rest_namespace: "/object-query/invoices/",
    url_template: "/object-query/invoices/:id"

  has_many :payment_methods, 
    rest_namespace: "/v1/payment-methods/credit-cards/accounts/", 
    result_key: "creditCards",
    url_template: "/v1/payment-methods/credit-cards/accounts/:id"

  has_many :subscriptions, 
    rest_namespace: "/v1/subscriptions/accounts/",
    url_template: "/v1/subscriptions/accounts/:id"
end

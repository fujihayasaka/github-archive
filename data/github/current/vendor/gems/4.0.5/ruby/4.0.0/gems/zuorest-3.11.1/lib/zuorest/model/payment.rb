class Zuorest::Model::Payment < Zuorest::Model::Base
  zuora_rest_namespace "/v1/object/payment/", url_template: "/v1/object/payment/:id"

  # Gateway Response if response is error.
  #
  # Returns an error message or nil.
  def error_message
    self[:GatewayResponse] if error?
  end

  # Returns true if response status is "Error"
  def error?
    status == "Error"
  end

  private

  def status
    self[:Status]
  end
end

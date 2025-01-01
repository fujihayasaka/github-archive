module Zuorest::RSASignature
  def create_rsa_signature(body, headers = {})
    post("/v1/rsa-signatures", body:, headers:, url_template: "/v1/rsa-signatures")
  end
end

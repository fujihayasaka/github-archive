# typed: true
# frozen_string_literal: true

class Stafftools::DecryptFlamegraphController < StafftoolsController

  def new
    render "stafftools/decrypt_flamegraph/new"
  end

  def create
    redirect_for_invalid_upload and return unless params[:flamegraph]

    box = RbNaCl::SimpleBox.from_secret_key(GitHub.flamegraph_encryption_key)
    decrypted = box.decrypt(params[:flamegraph].read)

    send_data(
      decrypted,
      filename: "decrypted_#{params[:flamegraph].original_filename}",
      type: "application/octet-stream",
      disposition: "attachment"
    )
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    redirect_for_invalid_upload
  end

  private

  def redirect_for_invalid_upload
    flash[:error] = "invalid file"
    redirect_to stafftools_decrypt_flamegraph_path
  end
end

# typed: true

class CreateAuthenticationTokensToLodge < ActiveRecord::Migration[7.0]
  self.use_connection_class(ApplicationRecord::Lodge)

  def change
    # noop
  end
end

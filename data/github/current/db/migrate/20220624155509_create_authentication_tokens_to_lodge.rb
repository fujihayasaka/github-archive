# typed: true

# rubocop:disable GitHub/SpecifyDefaultCharsetAndCollation
# rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys
# rubocop:disable GitHub/ReferencingColumnsMustBeBigint

class CreateAuthenticationTokensToLodge < ActiveRecord::Migration[7.0]
  self.use_connection_class(ApplicationRecord::Lodge)

  def change
    # noop
  end
end

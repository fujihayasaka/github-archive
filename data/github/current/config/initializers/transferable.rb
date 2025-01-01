# typed: true
# frozen_string_literal: true

module Transferable
  def transfer_to(model)
    T.bind(self, ActiveRecord::Associations::CollectionProxy)

    reflection = proxy_association.reflection

    if reflection.type
      update_all(reflection.type => model.class.to_s, reflection.foreign_key => model.id)
    else
      update_all(reflection.foreign_key => model.id) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
    end
  end
end

ActiveRecord::Associations::CollectionProxy.include Transferable

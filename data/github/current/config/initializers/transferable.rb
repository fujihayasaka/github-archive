# typed: true
# frozen_string_literal: true

module Transferable
  TRANSFERABLE_BATCH_LIMIT = 100

  def transfer_to(model)
    T.bind(self, ActiveRecord::Associations::CollectionProxy)

    reflection = proxy_association.reflection

    update_all_args = reflection.type ? { reflection.type => model.class.to_s, reflection.foreign_key => model.id } : { reflection.foreign_key => model.id }

    if FeatureFlag.vexi.enabled?(:octoshift_mannequin_reclaiming_in_batches, default: false)
      in_batches(of: TRANSFERABLE_BATCH_LIMIT) do |batch|
        self.model.throttle do
          batch.update_all(**update_all_args) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
        end
      end
    else
      update_all(**update_all_args) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
    end
  end
end

ActiveRecord::Associations::CollectionProxy.include Transferable

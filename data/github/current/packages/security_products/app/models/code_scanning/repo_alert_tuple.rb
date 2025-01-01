# typed: strict
# frozen_string_literal: true

module CodeScanning
  class RepoAlertTuple < T::Struct
    extend T::Sig

    prop :repository_id, Integer
    prop :alert_number, Integer
  end
end

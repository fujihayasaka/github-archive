# typed: strict
# frozen_string_literal: true

module CodeScanning
  class RepoAlertTuple < T::Struct
    prop :repository_id, Integer
    prop :alert_number, Integer
  end
end

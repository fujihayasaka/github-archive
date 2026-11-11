# typed: true
# frozen_string_literal: true

GlobalInstrumenter.subscribe("user.destroy") do |_name, _start, _ending, _transaction_id, payload|
  user = payload[:user]
  next unless user&.id

  InProductTargeting.domain.delete_matches_for_user(user_id: user.id)
end

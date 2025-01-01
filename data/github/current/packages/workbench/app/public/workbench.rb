# typed: strict
# frozen_string_literal: true

# For now we're just doing some KV storage with loose objects
# Will improve this when we get a real domain with real models
module Workbench
  sig do
    params(
      user_id: Integer,
      name: String,
      attributes: T::Hash[Symbol, T.untyped],
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.create_workbench(user_id, name, attributes = {})
    uuid = SecureRandom.uuid
    workbenches = ::Workbench.load_workbenches(user_id)
    workbenches << { id: uuid, name: name }
    ::Workbench.save_workbenches(user_id, workbenches)

    workbench = attributes.merge({
      id: uuid,
      name: name,
    })
    ::Workbench.save_workbench(user_id, uuid, JSON.dump(workbench))

    workbench
  end

  sig do
    params(
      user_id: Integer,
    ).returns(T::Array[T::Hash[String, T.untyped]])
  end
  def self.load_workbenches(user_id)
    list_key = "#{user_id}/workbenches"
    workbenches_raw = Copilot::Runtime::Kv.store.get(list_key).value { "[]" }
    workbenches_raw = "[]" if workbenches_raw.nil?
    workbenches = JSON.parse(workbenches_raw)
    workbenches
  end

  sig do
    params(
      user_id: Integer,
      workbenches: T::Array[T::Hash[String, T.untyped]],
    ).void
  end
  def self.save_workbenches(user_id, workbenches)
    list_key = "#{user_id}/workbenches"
    ActiveRecord::Base.connected_to(role: :writing) do
      Copilot::Runtime::Kv.store.set(list_key, JSON.dump(workbenches))
    end
  end

  sig do
    params(
      user_id: Integer,
      workbench_id: String,
    ).returns(T.nilable(T::Hash[String, T.untyped]))
  end
  def self.load_workbench(user_id, workbench_id)
    key = "#{user_id}/workbenches/#{workbench_id}"

    raw = Copilot::Runtime::Kv.store.get(key).value { "{}" }
    return nil unless raw

    JSON.parse(raw)
  end

  sig do
    params(
      user_id: Integer,
      workbench_id: String,
      workbench_raw: String,
    ).void
  end
  def self.save_workbench(user_id, workbench_id, workbench_raw)
    key = "#{user_id}/workbenches/#{workbench_id}"
    ActiveRecord::Base.connected_to(role: :writing) do
      Copilot::Runtime::Kv.store.set(key, workbench_raw)
    end
  end

  sig do
    params(
      user_id: Integer,
      workbench_id: String,
    ).void
  end
  def self.delete_workbench(user_id, workbench_id)
    workbenches = ::Workbench.load_workbenches(user_id)
    workbenches.delete_if do |workbench|
      workbench["id"] == workbench_id
    end
    ::Workbench.save_workbenches(user_id, workbenches)

    key = "#{user_id}/workbenches/#{workbench_id}"
    ActiveRecord::Base.connected_to(role: :writing) do
      Copilot::Runtime::Kv.store.del(key)
    end
  end
end

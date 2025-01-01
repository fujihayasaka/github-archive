# typed: true
# frozen_string_literal: true
require "github-launch"

class Actions::MachineSpec

  class MachineSpecGpu
    attr_reader :name, :count, :memory_gb
    def initialize(name: nil, count: 0, memory_gb: 0)
      @name = name
      @count = count
      @memory_gb = memory_gb
    end
  end

  attr_reader :id, :type, :architecture, :cpu_cores, :memory_gb, :storage_gb,  :documentation_url
  attr_reader :display_title, :display_main_info, :display_additional_info, :display_show_docs_url

  sig { returns(T.nilable(MachineSpecGpu)) }
  attr_reader :gpu

  def initialize(id: nil, type: nil, architecture: nil, cpu_cores: 0, memory_gb: 0, storage_gb: 0, documentation_url: nil, gpu: nil)
    @id = id
    @type = type
    @architecture = architecture.present? ? architecture : "X64"
    @cpu_cores = cpu_cores
    @memory_gb = memory_gb
    @storage_gb = storage_gb
    @documentation_url = documentation_url
    @gpu = gpu

    init_display_text
  end

  def init_display_text
    cpu_cores_text = "#{@cpu_cores}-cores"
    ram_gb_text = "#{@memory_gb} GB RAM"
    storage_gb_text = "#{@storage_gb} GB SSD"

    case @type
    when "gpu_optimized"
      gpu_card_text = "#{@gpu.count} x #{@gpu.name}"
      gpu_vram_text = "#{@gpu.memory_gb} GB VRAM"
      @display_title = "#{gpu_card_text} · #{gpu_vram_text}"
      @display_main_info = "#{gpu_card_text} · #{gpu_vram_text}"
      @display_additional_info = "#{cpu_cores_text} · #{ram_gb_text} · #{storage_gb_text}"
      @display_show_docs_url = true
    else
      @display_title = "#{cpu_cores_text} · #{ram_gb_text} · #{storage_gb_text}"
      @display_main_info = cpu_cores_text
      @display_additional_info = "#{ram_gb_text} · #{storage_gb_text}"
      @display_show_docs_url = false
    end
  end

  sig { params(owner: T.any(Organization, Business)).returns(T::Array[Actions::MachineSpec]) }
  def self.machine_specs_for(owner)
    resp = Launch::Twirp::larger_runners_client.list_machine_specs(owner)

    machine_specs = from_rpc_collection(resp.value&.machineSpecs || [])
    machine_specs.sort_by { |spec| [spec.cpu_cores, spec.memory_gb, spec.storage_gb] }
  end

  sig { params(entities: T.untyped).returns(T::Array[Actions::MachineSpec]) }
  def self.from_rpc_collection(entities)
    # Remove nil entries, ensure single objects are returned as an array
    Array.wrap(entities.filter_map { |entity| from_rpc_object(entity) })
  end

  sig { params(entity: T.untyped).returns(T.nilable(Actions::MachineSpec)) }
  def self.from_rpc_object(entity)
    return nil if entity.nil? || entity.id.empty?

    new(
      id: entity.id,
      type: entity.type,
      architecture: entity.architecture,
      cpu_cores: entity.cpu_cores,
      memory_gb: entity.memory_gb,
      storage_gb: entity.storage_gb,
      gpu: entity.gpu.present? ? MachineSpecGpu.new(name: entity.gpu.name, count: entity.gpu.count, memory_gb: entity.gpu.memory_gb) : nil,
      documentation_url: entity.documentation_url,
    )
  end

  def is_gpu_spec?
    @type == "gpu_optimized"
  end
end

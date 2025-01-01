class FakeSink
  include Enumerable

  delegate :each, :empty?, to: :items

  attr_reader :items

  def initialize
    @items = []
    @pending = []
  end

  def publish(item)
    @pending << item
  end

  def <<(item)
    @items << item
  end

  def count
    @items.count
  end

  def flush
    @items.concat(@pending)
    @pending.clear
  end

  def items # rubocop:disable Lint/DuplicateMethods
    @items
  end

  def consume(&block)
    @items.map { |item| wrap_item_in_consumer_message(item) }.each(&block)
  end

  private

  def wrap_item_in_consumer_message(item)
    Hydro::Consumer::ConsumerMessage.new(
      source_message: nil,
      schema: "",
      timestamp: Time.now,
      value: item,
    )
  end
end

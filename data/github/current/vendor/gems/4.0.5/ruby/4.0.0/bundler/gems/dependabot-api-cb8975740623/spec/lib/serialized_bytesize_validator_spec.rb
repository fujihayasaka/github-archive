# frozen_string_literal: true

require "rails_helper"
require "serialized_bytesize_validator"

RSpec.describe SerializedBytesizeValidator, type: :model do
  self.use_transactional_tests = false

  def create_notes_table
    table_name = "#{ActiveRecord::Base.table_name_prefix}notes"
    options = { charset: "utf8mb4", collation: "utf8mb4_general_ci", force: true }
    ActiveRecord::Base.connection.create_table table_name, **options do |t|
      t.string :content, limit: 100
    end
  end

  def drop_notes_table
    table_name = "#{ActiveRecord::Base.table_name_prefix}notes"
    ActiveRecord::Base.connection.drop_table(table_name, if_exists: true)
  end

  def generate_json(serialized_bytesize:, fill_value: "x")
    prefix = "{\"o\":\""
    suffix = "\"}"

    buffer = StringIO.new
    buffer << prefix

    current_fill_value = fill_value
    remaining_bytes = serialized_bytesize - prefix.bytesize - suffix.bytesize
    while remaining_bytes > 0
      current_fill_value = "x" if current_fill_value.bytesize > remaining_bytes
      buffer << current_fill_value
      remaining_bytes -= current_fill_value.bytesize
    end

    buffer << suffix

    raise "Expected #{serialized_bytesize} bytes, got #{buffer.string.bytesize} bytes" \
      unless buffer.string.bytesize == serialized_bytesize

    JSON.parse(buffer.string)
  end

  around do |example|
    create_notes_table
    example.run
    drop_notes_table
  end

  before do
    stub_const("Note", note_class)
  end

  let(:note_class) do
    Class.new(ApplicationRecord) do
      serialize :content, coder: JSON
    end
  end

  it "raises an ArgumentError when the :maximum option is missing" do
    expect do
      note_class.validates :content, serialized_bytesize: {}
    end.to raise_error(ArgumentError, "The :maximum option is required.")
  end

  it "raises an ArgumentError when the :maximum option is not a positive integer" do
    expect do
      note_class.validates :content, serialized_bytesize: { maximum: 0 }
    end.to raise_error(ArgumentError, "The :maximum option must be a positive integer.")
  end

  context "when the configured :maximum is greater than the database column limit" do
    before do
      note_class.validates :content, serialized_bytesize: { maximum: 102 }
    end

    it "raises a database adapter error when the bytesize of the serialized attribute " \
      "exceeds the database column limit" do
      content = generate_json(serialized_bytesize: 101)
      note = Note.new(content: content)

      expect(note).to be_valid
      expect { note.save! }.to raise_error(ActiveRecord::ActiveRecordError)
    end
  end

  context "when the configured :maximum is less than or equal to the database column limit" do
    before do
      note_class.validates :content, serialized_bytesize: { maximum: 25 }
    end

    it "is invalid when the bytesize of the serialized attribute is greater than the configured :maximum" do
      content = generate_json(serialized_bytesize: 26)
      note = Note.new(content: content)

      expect(note).not_to be_valid

      error_message = <<~MESSAGE.strip
        is too long (maximum serialized size: 25 bytes, actual: #{note.attributes_for_database['content'].bytesize})
      MESSAGE
      expect(note.errors[:content]).to include(error_message)
    end

    it "is invalid when the bytesize of the serialized attribute is greater than the configured :maximum " \
      "even if the character length of the serialized attribute is less than the configured :maximum" do
      # Generate some JSON containing characters that will take up two bytes when UTF-8 encoded:
      content = generate_json(serialized_bytesize: 26, fill_value: "ü")
      expect(content.to_json.length).to eq(17)
      expect(content.to_json.bytesize).to eq(26)

      note = Note.new(content: content)

      expect(note).not_to be_valid

      error_message = <<~MESSAGE.strip
        is too long (maximum serialized size: 25 bytes, actual: #{note.attributes_for_database['content'].bytesize})
      MESSAGE
      expect(note.errors[:content]).to include(error_message)
    end

    it "is valid when the attribute is nil" do
      note = Note.new(content: nil)

      expect(note).to be_valid
      expect { note.save! }.to change(Note, :count).by(1)
      expect(Note.last.content).to eq(nil)
    end

    it "is valid when the bytesize of the serialized attribute is less than the configured :maximum" do
      content = generate_json(serialized_bytesize: 24)
      note = Note.new(content: content)

      expect(note).to be_valid
      expect { note.save! }.to change(Note, :count).by(1)
      expect(Note.last.content).to eq(content)
    end

    it "is valid when the bytesize of the serialized attribute is equal to the configured :maximum" do
      content = generate_json(serialized_bytesize: 25)
      note = Note.new(content: content)

      expect(note).to be_valid
      expect { note.save! }.to change(Note, :count).by(1)
      expect(Note.last.content).to eq(content)
    end
  end
end

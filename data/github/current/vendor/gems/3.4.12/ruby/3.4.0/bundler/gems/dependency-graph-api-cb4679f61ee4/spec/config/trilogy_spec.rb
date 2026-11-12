require 'rails_helper'

describe "trilogy" do
  it "retries on connection errors" do
    connection = ActiveRecord::Base.connection

    raw_connection = connection.instance_variable_get("@raw_connection")
    expect(raw_connection).to receive(:query).once.and_raise(Trilogy::EOFError.new("trilogy_query_recv: TRILOGY_CLOSED_CONNECTION"))

    $ready = true
    result = nil
    expect do
      result = connection.execute "SELECT * FROM dg_vulnerable_version_ranges"
    end.not_to raise_error

    expect(result).to be_a(Trilogy::Result)
  end
end

# frozen_string_literal: true

require "test_helper"

class TestHarvester < Minitest::Test
  def setup
    @h = MacSetup::Harvester.new
  end

  # coerce_value translates `defaults read` stdout into the YAML value
  # we emit to macos_defaults_discovered.yml. `defaults read` prints
  # booleans as "1"/"0" (and sometimes "true"/"false") and numbers as
  # base-10 strings.

  def test_coerce_bool_truthy_forms
    %w[1 true TRUE True].each do |raw|
      assert_equal true, @h.send(:coerce_value, raw, "bool"), "expected #{raw.inspect} → true"
    end
  end

  def test_coerce_bool_falsy_forms
    ["0", "false", "False", "FALSE", "", "anything-else"].each do |raw|
      assert_equal false, @h.send(:coerce_value, raw, "bool"), "expected #{raw.inspect} → false"
    end
  end

  def test_coerce_int
    assert_equal 42, @h.send(:coerce_value, "42", "int")
    assert_equal(-7, @h.send(:coerce_value, "-7", "int"))
    # `defaults read` would never return this, but the coercion should
    # still behave (String#to_i parses the numeric prefix).
    assert_equal 12, @h.send(:coerce_value, "12 garbage", "int")
    assert_equal 0, @h.send(:coerce_value, "not-a-number", "int")
  end

  def test_coerce_float
    assert_in_delta 2.5, @h.send(:coerce_value, "2.5", "float"), 0.001
    assert_in_delta 0.0, @h.send(:coerce_value, "0", "float"), 0.001
  end

  def test_coerce_string_passes_raw_through
    assert_equal "Dark", @h.send(:coerce_value, "Dark", "string")
    assert_equal "right", @h.send(:coerce_value, "right", "string")
  end

  def test_coerce_unknown_type_passes_raw_through
    # Defensive: any type we haven't enumerated returns the raw string
    # rather than raising. New types can be added to the YAML format
    # without breaking the harvester.
    assert_equal "whatever", @h.send(:coerce_value, "whatever", "array-of-strings")
  end
end

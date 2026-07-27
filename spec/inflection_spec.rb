# frozen_string_literal: true

module DefineSimpleActionSpec
  module Nested
    class Widget; end
  end
end

RSpec.describe "DefineSimpleAction module-level helpers" do
  describe ".constantize" do
    it "resolves a nested constant by its full name" do
      expect(DefineSimpleAction.constantize("DefineSimpleActionSpec::Nested::Widget"))
        .to eq(DefineSimpleActionSpec::Nested::Widget)
    end

    it "strips a leading ::" do
      expect(DefineSimpleAction.constantize("::DefineSimpleActionSpec::Nested::Widget"))
        .to eq(DefineSimpleActionSpec::Nested::Widget)
    end

    it "raises NameError for an unknown constant" do
      expect { DefineSimpleAction.constantize("Nope::NotHere") }.to raise_error(NameError)
    end
  end

  describe ".safe_constantize" do
    it "returns the constant when it exists" do
      expect(DefineSimpleAction.safe_constantize("DefineSimpleActionSpec::Nested::Widget"))
        .to eq(DefineSimpleActionSpec::Nested::Widget)
    end

    it "returns nil instead of raising for an unknown constant" do
      expect(DefineSimpleAction.safe_constantize("Nope::NotHere")).to be_nil
    end
  end

  describe "DefineSimpleAction::INFLECTOR" do
    it "camelizes snake_case action names (dry-inflector, no ActiveSupport)" do
      expect(DefineSimpleAction::INFLECTOR.camelize("batch_destroy")).to eq("BatchDestroy")
      expect(DefineSimpleAction::INFLECTOR.camelize("index")).to eq("Index")
    end
  end
end

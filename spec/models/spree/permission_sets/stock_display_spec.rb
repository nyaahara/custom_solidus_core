require 'spec_helper'

describe Spree::PermissionSets::StockDisplay do
  let(:ability) { DummyAbility.new }

  subject { ability }

  context "when activated" do
    before do
      described_class.new(ability).activate!
    end

    it { is_expected.to be_able_to(:display, Spree::StockItem) }
    it { is_expected.to be_able_to(:display, Spree::StockTransfer) }
    it { is_expected.to be_able_to(:admin, Spree::StockItem) }
    it { is_expected.to be_able_to(:admin, Spree::StockTransfer) }
  end

  context "when not activated" do
    it { is_expected.not_to be_able_to(:display, Spree::StockItem) }
    it { is_expected.not_to be_able_to(:display, Spree::StockTransfer) }
    it { is_expected.not_to be_able_to(:admin, Spree::StockItem) }
    it { is_expected.not_to be_able_to(:admin, Spree::StockTransfer) }
  end
end


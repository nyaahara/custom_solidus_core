module Spree
  # Adjustments represent a change to the +item_total+ of an Order. Each
  # adjustment has an +amount+ that can be either positive or negative.
  #
  # Adjustments can be "opened" or "closed". Once an adjustment is closed, it
  # will not be automatically updated.
  #
  # == Boolean attributes
  #
  # 1. *mandatory*
  #
  #    If this flag is set to true then it means the the charge is required and
  #    will not be removed from the order, even if the amount is zero. In other
  #    words a record will be created even if the amount is zero. This is
  #    useful for representing things such as shipping and tax charges where
  #    you may want to make it explicitly clear that no charge was made for
  #    such things.
  #
  # 2. *eligible?*
  #
  #    This boolean attributes stores whether this adjustment is currently
  #    eligible for its order. Only eligible adjustments count towards the
  #    order's adjustment total. This allows an adjustment to be preserved if
  #    it becomes ineligible so it might be reinstated.
  class Adjustment < Spree::Base
    belongs_to :adjustable, polymorphic: true, touch: true
    belongs_to :source, polymorphic: true
    belongs_to :order, class_name: "Spree::Order"
    belongs_to :promotion_code, :class_name => 'Spree::PromotionCode'
    belongs_to :adjustment_reason, class_name: 'Spree::AdjustmentReason', inverse_of: :adjustments

    validates :adjustable, presence: true
    validates :order, presence: true
    validates :label, presence: true
    validates :amount, numericality: true
    validates :promotion_code, presence: true, if: :require_promotion_code?

    state_machine :state, initial: :open do
      event :close do
        transition from: :open, to: :closed
      end

      event :open do
        transition from: :closed, to: :open
      end
    end

    after_create :update_adjustable_adjustment_total
    after_destroy :update_adjustable_adjustment_total

    scope :open, -> { where(state: 'open') }
    scope :closed, -> { where(state: 'closed') }
    scope :cancellation, -> { where(source_type: 'Spree::UnitCancel') }
    scope :tax, -> { where(source_type: 'Spree::TaxRate') }
    scope :non_tax, -> do
      source_type = arel_table[:source_type]
      where(source_type.not_eq('Spree::TaxRate').or source_type.eq(nil))
    end
    scope :price, -> { where(adjustable_type: 'Spree::LineItem') }
    scope :shipping, -> { where(adjustable_type: 'Spree::Shipment') }
    scope :optional, -> { where(mandatory: false) }
    scope :eligible, -> { where(eligible: true) }
    scope :charge, -> { where("#{quoted_table_name}.amount >= 0") }
    scope :credit, -> { where("#{quoted_table_name}.amount < 0") }
    scope :nonzero, -> { where("#{quoted_table_name}.amount != 0") }
    scope :promotion, -> { where(source_type: 'Spree::PromotionAction') }
    scope :non_promotion, -> { where.not(source_type: 'Spree::PromotionAction') }
    scope :return_authorization, -> { where(source_type: "Spree::ReturnAuthorization") }
    scope :is_included, -> { where(included: true) }
    scope :additional, -> { where(included: false) }

    extend DisplayMoney
    money_methods :amount

    def closed?
      state == "closed"
    end

    def currency
      adjustable ? adjustable.currency : Spree::Config[:currency]
    end

    # @return [Boolean] true when this is a promotion adjustment (Promotion adjustments have a {PromotionAction} source)
    def promotion?
      source_type == 'Spree::PromotionAction'
    end

    # @return [Boolean] true when this is a tax adjustment (Tax adjustments have a {TaxRate} source)
    def tax?
      source_type == 'Spree::TaxRate'
    end

    # @return [Boolean] true when this is a cancellation adjustment (Cancellation adjustments have a {UnitCancel} source)
    def cancellation?
      source_type == 'Spree::UnitCancel'
    end

    # Recalculate and persist the amount from this adjustment's source based on
    # the adjustable ({Order}, {Shipment}, or {LineItem})
    #
    # If the adjustment has no source (such as when created manually from the
    # admin) or is closed, this is a noop.
    #
    # @param target [Spree::LineItem,Spree::Shipment,Spree::Order] Deprecated: the target to calculate against
    # @return [BigDecimal] New amount of this adjustment
    def update!(target = nil)
      if target
        ActiveSupport::Deprecation.warn("Passing a target to Adjustment#update! is deprecated. The adjustment will use the correct target from it's adjustable association.", caller)
      end
      return amount if closed?

      # If the adjustment has no source, do not attempt to re-calculate the amount.
      # Chances are likely that this was a manually created adjustment in the admin backend.
      if source.present?
        self.amount = source.compute_amount(target || adjustable)

        if promotion?
          self.eligible = source.promotion.eligible?(adjustable, promotion_code: promotion_code)
        end

        # Persist only if changed
        # This is only not a save! to avoid the extra queries to load the order
        # (for validations) and to touch the adjustment.
        update_columns(eligible: eligible, amount: amount, updated_at: Time.now) if changed?
      end
      amount
    end

    def currency
      adjustable ? adjustable.currency : Spree::Config[:currency]
    end

    private

    def update_adjustable_adjustment_total
      # Cause adjustable's total to be recalculated
      ItemAdjustments.new(adjustable).update
    end

    def require_promotion_code?
      promotion? && source.promotion.codes.any?
    end
  end
end

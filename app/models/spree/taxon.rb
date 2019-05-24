module Spree
  class Taxon < Spree::Base
    acts_as_nested_set dependent: :destroy

    belongs_to :taxonomy, class_name: 'Spree::Taxonomy', inverse_of: :taxons
    has_many :classifications, -> { order(:position) }, dependent: :delete_all, inverse_of: :taxon
    has_many :products, through: :classifications

    has_and_belongs_to_many :prototypes, join_table: :spree_taxons_prototypes

    before_create :set_permalink

    validates :name, presence: true
    validates :meta_keywords, length: { maximum: 255 }
    validates :meta_description, length: { maximum: 255 }
    validates :meta_title, length: { maximum: 255 }

    after_save :touch_ancestors_and_taxonomy
    after_touch :touch_ancestors_and_taxonomy

    has_attached_file :icon,
      styles: { mini: '32x32>', normal: '128x128>' },
      default_style: :mini,
      url: '/spree/taxons/:id/:style/:basename.:extension',
      path: ':rails_root/public/spree/taxons/:id/:style/:basename.:extension',
      default_url: '/assets/default_taxon.png'

    validates_attachment :icon,
      content_type: { content_type: ["image/jpg", "image/jpeg", "image/png", "image/gif"] }

    # @note This method is meant to be overridden on a store by store basis.
    # @return [Array] filters that should be used for a taxon
    def applicable_filters
      fs = []
      # fs << ProductFilters.taxons_below(self)
      ## unless it's a root taxon? left open for demo purposes

      fs << Spree::Core::ProductFilters.price_filter if Spree::Core::ProductFilters.respond_to?(:price_filter)
      fs << Spree::Core::ProductFilters.brand_filter if Spree::Core::ProductFilters.respond_to?(:brand_filter)
      fs
    end

    # @return [String] meta_title if set otherwise a string containing the
    #   root name and taxon name
    def seo_title
      unless meta_title.blank?
        meta_title
      else
        root? ? name : "#{root.name} - #{name}"
      end
    end

    # Sets this taxons permalink to a valid url encoded string based on its
    # name and its parents permalink (if present.)
    def set_permalink
      if parent.present?
        self.permalink = [parent.permalink, (permalink.blank? ? name.to_url : permalink.split('/').last)].join('/')
      else
        self.permalink = name.to_url if permalink.blank?
      end
    end

    # @return [String] this taxon's permalink
    def to_param
      permalink
    end

    # @return [ActiveRecord::Relation<Spree::Product>] the active products the
    #   belong to this taxon
    def active_products
      products.active
    end

    # @return [String] this taxon's ancestors names followed by its own name,
    #   separated by arrows
    def pretty_name
      ancestor_chain = self.ancestors.inject("") do |name, ancestor|
        name += "#{ancestor.name} -> "
      end
      ancestor_chain + "#{name}"
    end

    # @see https://github.com/spree/spree/issues/3390
    def child_index=(idx)
      # awesome_nested_set sorts by :lft and :rgt. This call re-inserts the
      # child node so that its resulting position matches the observable
      # 0-indexed position.
      #
      # NOTE: no :position column needed - awesom_nested_set doesn't handle the
      # reordering if you bring your own :order_column.
      move_to_child_with_index(parent, idx.to_i) unless self.new_record?
    end

    private

    def touch_ancestors_and_taxonomy
      # Touches all ancestors at once to avoid recursive taxonomy touch, and reduce queries.
      self.class.where(id: ancestors.pluck(:id)).update_all(updated_at: Time.now)
      # Have taxonomy touch happen in #touch_ancestors_and_taxonomy rather than association option in order for imports to override.
      taxonomy.try!(:touch)
    end
  end
end
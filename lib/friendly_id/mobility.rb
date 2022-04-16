require "friendly_id"
require "friendly_id/mobility/version"
require "friendly_id/slug_decorator"

module FriendlyId
  module Mobility
    class << self
      def setup(model_class)
        model_class.friendly_id_config.use :slugged
        if model_class.friendly_id_config.uses? :history
          model_class.instance_eval do
            friendly_id_config.finder_methods = FriendlyId::Mobility::FinderMethods
          end
        end
        if model_class.friendly_id_config.uses? :finders
          warn "[FriendlyId] The Mobility add-on is not compatible with the Finders add-on. " \
            "Please remove one or the other from the #{model_class} model."
        end
      end

      def included(model_class)
        advise_against_untranslated_model(model_class)

        mod = Module.new do
          def friendly
            super.extending(::Mobility::Plugins::ActiveRecord::Query::QueryExtension)
          end
        end
        model_class.send :extend, mod
      end

      def advise_against_untranslated_model(model)
        field = model.friendly_id_config.query_field
        if model.included_modules.grep(::Mobility::Translations).empty? || model.mobility_attributes.exclude?(field.to_s)
          raise "[FriendlyId] You need to translate the '#{field}' field with " \
            "Mobility (add 'translates :#{field}' in your model '#{model.name}')"
        end
      end
      private :advise_against_untranslated_model
    end

    def set_friendly_id(text, locale = nil)
      ::Mobility.with_locale(locale || ::Mobility.locale) do
        set_slug normalize_friendly_id(text)
      end
    end

    def mobility_table_backend_translations
      return [] unless self.class.mobility_attributes.include?(friendly_id_config.slug_column)
      return [] unless mobility_backends[friendly_id_config.slug_column].kind_of?(::Mobility::Backends::ActiveRecord::Table)
      send(mobility_backends[friendly_id_config.slug_column].association_name)
    end

    def should_generate_new_friendly_id?
      send(friendly_id_config.slug_column, locale: ::Mobility.locale).nil? && !send(friendly_id_config.base).nil?
    end

    def set_slug(normalized_slug = nil)
      m_translations = mobility_table_backend_translations.to_a
      if m_translations.any?
        m_translations.each do |translation|
          ::Mobility.with_locale(translation.locale) do
            super
            # I would expect this to happen automatically by Mobility, but it doesn't
            # We don't use locale: ::Mobility.locale intentionally, so fallbacks can be applied if it's blank
            translation[friendly_id_config.slug_column] = send(friendly_id_config.slug_column)
          end
        end
      else
        super
      end
    end
    private

    # TODO: take into account mobility plugins like :history and :scoped!
    def scope_for_slug_generator
      scope = self.class.base_class.unscoped
      scope = scope.friendly unless scope.respond_to?(:exists_by_friendly_id?)
      primary_key_name = self.class.primary_key
      scope.where(self.class.base_class.arel_table[primary_key_name].not_eq(send(primary_key_name)))
    end

    module FinderMethods
      include ::FriendlyId::History::FinderMethods

      def exists_by_friendly_id?(id)
        where(friendly_id_config.query_field => parse_friendly_id(id)).exists?
      end

      private

      def first_by_friendly_id(id)
        fallback_locales = [::Mobility.locale]
        begin
          backend = model.mobility_backend_class(friendly_id_config.slug_column)
          fallback_locales.concat(backend.fallbacks[::Mobility.locale])
          fallback_locales.uniq!
        rescue KeyError # backend not found
        end

        fallback_locales.each do |locale|
          ::Mobility.with_locale(locale) do
            find_by(friendly_id_config.query_field => parse_friendly_id(id)).tap do |result|
              return result if result
            end
          end
        end

        nil
      end
    end
  end
end

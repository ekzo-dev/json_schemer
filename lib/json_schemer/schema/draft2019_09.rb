# frozen_string_literal: true
module JSONSchemer
  module Schema
    class Draft2019_09 < Base
      SUPPORTED_FORMATS = Set[
        'date-time',
        'date',
        'time',
        'email',
        'idn-email',
        'hostname',
        'idn-hostname',
        'ipv4',
        'ipv6',
        'uri',
        'uri-reference',
        'iri',
        'iri-reference',
        'uri-template',
        'json-pointer',
        'relative-json-pointer',
        'regex',
        'uuid',
        'duration'
      ].freeze

    private

      def supported_format?(format)
        SUPPORTED_FORMATS.include?(format)
      end

      def validate_ref(instance, ref, &block)
        ref_uri = join_uri(instance.base_uri, ref)

        ref_uri_pointer = ''
        if valid_json_pointer?(ref_uri.fragment)
          ref_uri_pointer = ref_uri.fragment
          ref_uri.fragment = nil
        end

        ref_object = if ids.key?(ref_uri) || ref_uri.to_s.empty? || ref_uri.to_s == @base_uri.to_s
                       self
                     else
                       child(resolve_ref(ref_uri), base_uri: ref_uri)
                     end

        ref_schema, ref_schema_pointer, ref_parent_base_uri = ref_object.ids[ref_uri] || [ref_object.root, '', ref_uri]

        ref_uri_pointer_parts = Hana::Pointer.parse(URI.decode_www_form_component(ref_uri_pointer))
        schema, base_uri = ref_uri_pointer_parts.reduce([ref_schema, ref_parent_base_uri]) do |(obj, uri), token|
          if obj.is_a?(Array)
            [obj.fetch(token.to_i), uri]
          else
            [obj.fetch(token), join_uri(uri, obj[id_keyword])]
          end
        end

        transfer_keywords = instance.schema.reject { |k, _| k.start_with?('$') }
        subinstance = instance.merge(
          schema: schema.is_a?(Hash) ? schema.merge(transfer_keywords) : schema,
          schema_pointer: "#{ref_schema_pointer}#{ref_uri_pointer}",
          base_uri: base_uri
        )

        ref_object.validate_instance(subinstance, &block)
      end
    end
  end
end

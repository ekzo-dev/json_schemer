require 'test_helper'

class JSONSchemerTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil(JSONSchemer::VERSION)
  end

  def test_it_does_something_useful
    schema = {
      'type' => 'object',
      'maxProperties' => 4,
      'minProperties' => 1,
      'required' => [
        'one'
      ],
      'properties' => {
        'one' => {
          'type' => 'string',
          'maxLength' => 5,
          'minLength' => 3,
          'pattern' => '\w+'
        },
        'two' => {
          'type' => 'integer',
          'minimum' => 10,
          'maximum' => 100,
          'multipleOf' => 5
        },
        'three' => {
          'type' => 'array',
          'maxItems' => 2,
          'minItems' => 2,
          'uniqueItems' => true,
          'contains' => {
            'type' => 'integer'
          }
        }
      },
      'additionalProperties' => {
        'type' => 'string'
      },
      'propertyNames' => {
        'type' => 'string',
        'pattern' => '\w+'
      },
      'dependencies' => {
        'one' => [
          'two'
        ],
        'two' => {
          'minProperties' => 1
        }
      }
    }
    data = {
      'one' => 'value',
      'two' => 100,
      'three' => [1, 2],
      '123' => 'x'
    }
    schema = JSONSchemer.schema(schema)
    assert(schema.valid?(data))
    errors = schema.validate(data)
    assert(errors.none?)
  end

  def test_it_does_not_fail_when_the_schema_is_completely_empty
    schema = {}
    data = {
      'a' => 1
    }
    assert(JSONSchemer.schema(schema).valid?(data))
    assert_equal({ 'a' => 1 }, data)
  end

  def test_required_validation_adds_missing_keys
    schema = JSONSchemer.schema(Pathname.new(__dir__).join('schemas', 'schema1.json'))
    error = schema.validate({ 'id' => 1 }).first
    assert_equal('required', error.fetch('type'))
    assert_equal({ 'missing_keys' => ['a'] }, error.fetch('details'))
  end

  def test_it_handles_json_strings
    schema = JSONSchemer.schema('{ "type": "integer" }')
    assert(schema.valid?(1))
    refute(schema.valid?('1'))
  end

  def test_it_checks_for_symbol_keys
    assert_raises(JSONSchemer::InvalidSymbolKey) { JSONSchemer.schema({ :type => 'integer' }) }
    schema = JSONSchemer.schema(
      { '$ref' => 'http://example.com' },
      :ref_resolver => proc do |uri|
        { :type => 'integer' }
      end
    )
    assert_raises(JSONSchemer::InvalidSymbolKey) { schema.valid?(1) }
  end

  def test_it_returns_nested_errors
    root = {
      'type' => 'object',
      'required' => [
        'numberOfModules'
      ],
      'properties' => {
        'numberOfModules' => {
          'allOf' => [
            {
              'not' => {
                'type' => 'integer',
                'minimum' => 38
              }
            },
            {
              'not' => {
                'type' => 'integer',
                'maximum' => 37,
                'minimum' => 25
              }
            },
            {
              'not' => {
                'type' => 'integer',
                'maximum' => 24,
                'minimum' => 12
              }
            }
          ],
          'anyOf' => [
            { 'type' => 'integer' },
            { 'type' => 'string' }
          ],
          'oneOf' => [
            { 'type' => 'integer' },
            { 'type' => 'integer' },
            { 'type' => 'boolean' }
          ]
        }
      }
    }
    schema = JSONSchemer.schema(root)
    assert_equal(
      {
        'data' => 32,
        'data_pointer' => '/numberOfModules',
        'schema' => {
          'type' => 'integer',
          'maximum' => 37,
          'minimum' => 25
        },
        'schema_pointer' => '/properties/numberOfModules/allOf/1/not',
        'root_schema' => root,
        'type' => 'not'
      },
      schema.validate({ 'numberOfModules' => 32 }).first
    )
    assert_equal(
      {
        'data' => true,
        'data_pointer' => '/numberOfModules',
        'schema' => {
          'type' => 'integer'
        },
        'schema_pointer' => '/properties/numberOfModules/anyOf/0',
        'root_schema' => root,
        'type' => 'integer'
      },
      schema.validate({ 'numberOfModules' => true }).first
    )
    assert_equal(
      {
        'data' => 8,
        'data_pointer' => '/numberOfModules',
        'schema' => root.fetch('properties').fetch('numberOfModules'),
        'schema_pointer' => '/properties/numberOfModules',
        'root_schema' => root,
        'type' => 'oneOf'
      },
      schema.validate({ 'numberOfModules' => 8 }).first
    )
  end

  def test_it_validates_correctly_custom_keywords
    options = {
      keywords: {
        'ignored' => nil,
        'even' => lambda do |data, curr_schema, _pointer|
          curr_schema.fetch('even') == data.to_i.even?
        end
      }
    }

    schema = JSONSchemer.schema({ 'even' => true }, **options)
    assert(schema.valid?(2))
    refute(schema.valid?(3))

    options = {
      keywords: {
        'two' => lambda do |data, curr_schema, _pointer|
          if curr_schema.fetch('two') == (data == 2)
            []
          else
            ['error1', 'error2']
          end
        end
      }
    }

    schema = JSONSchemer.schema({ 'two' => true }, **options)
    assert_equal([], schema.validate(2).to_a)
    assert_equal(['error1', 'error2'], schema.validate(3).to_a)
    refute(schema.valid?(3))
  end

  def test_it_handles_multiple_of_floats
    assert(JSONSchemer.schema({ 'multipleOf' => 0.01 }).valid?(8.61))
    refute(JSONSchemer.schema({ 'multipleOf' => 0.01 }).valid?(8.666))
    assert(JSONSchemer.schema({ 'multipleOf' => 0.001 }).valid?(8.666))
  end

  def test_it_escapes_json_pointer_tokens
    schemer = JSONSchemer.schema(
      {
        'type' => 'object',
        'properties' => {
          'foo/bar~' => {
            'type' => 'string'
          }
        }
    }
    )
    errors = schemer.validate({ 'foo/bar~' => 1 }).to_a
    assert_equal(1, errors.size)
    assert_equal('/foo~1bar~0', errors.first.fetch('data_pointer'))
    assert_equal('/properties/foo~1bar~0', errors.first.fetch('schema_pointer'))
  end

  def test_it_ignores_invalid_types
    assert(JSONSchemer.schema({ 'type' => 'invalid' }).valid?({}))
    assert(JSONSchemer.schema({ 'type' => Object.new }).valid?({}))
  end

  def test_it_raises_for_unsupported_content_encoding
    assert_raises(NotImplementedError) { JSONSchemer.schema({ 'contentEncoding' => '7bit' }).valid?('') }
  end

  def test_it_raises_for_unsupported_content_media_type
    assert_raises(NotImplementedError) { JSONSchemer.schema({ 'contentMediaType' => 'application/xml' }).valid?('') }
  end

  def test_it_allows_validating_schemas
    valid_draft7_schema = { '$ref' => '#/definitions/~1some~1%7Bid%7D' }
    invalid_draft7_schema = { '$ref' => '#/definitions/~1some~1{id}' }
    valid_draft4_schema = invalid_draft7_schema
    invalid_draft4_schema = { 'properties' => { 'x' => { 'exclusiveMaximum' => true } } }
    valid_detected_draft4_schema = valid_draft4_schema.merge('$schema' => 'http://json-schema.org/draft-04/schema#')
    invalid_detected_draft4_schema = invalid_draft4_schema.merge('$schema' => 'http://json-schema.org/draft-04/schema#')
    format_error = {
      'data' => '#/definitions/~1some~1{id}',
      'data_pointer' => '/$ref',
      'schema' => { 'type' => 'string', 'format' => 'uri-reference' },
      'schema_pointer' => '/properties/$ref',
      'root_schema' => JSONSchemer::DEFAULT_SCHEMA_CLASS.meta_schema,
      'type' => 'format'
    }
    required_error = {
      'data' => { 'exclusiveMaximum' => true },
      'data_pointer' => '/properties/x',
      'schema' => { 'required' => ['maximum'] },
      'schema_pointer' => '/dependencies/exclusiveMaximum',
      'root_schema' => JSONSchemer::Schema::Draft4.meta_schema,
      'type' => 'required',
      'details' => { 'missing_keys' => ['maximum'] }
    }

    assert(JSONSchemer.valid_schema?(valid_draft7_schema))
    refute(JSONSchemer.valid_schema?(invalid_draft7_schema))
    assert(JSONSchemer.schema(valid_draft7_schema).valid_schema?)
    refute(JSONSchemer.schema(invalid_draft7_schema).valid_schema?)

    assert_empty(JSONSchemer.validate_schema(valid_draft7_schema).to_a)
    assert_equal([format_error], JSONSchemer.validate_schema(invalid_draft7_schema).to_a)
    assert_empty(JSONSchemer.schema(valid_draft7_schema).validate_schema.to_a)
    assert_equal([format_error], JSONSchemer.schema(invalid_draft7_schema).validate_schema.to_a)

    assert(JSONSchemer.valid_schema?(valid_draft4_schema, default_schema_class: JSONSchemer::Schema::Draft4))
    refute(JSONSchemer.valid_schema?(invalid_draft4_schema, default_schema_class: JSONSchemer::Schema::Draft4))
    assert(JSONSchemer::valid_schema?(valid_detected_draft4_schema))
    refute(JSONSchemer::valid_schema?(invalid_detected_draft4_schema))

    assert_empty(JSONSchemer.validate_schema(valid_draft7_schema, default_schema_class: JSONSchemer::Schema::Draft4).to_a)
    assert_equal([required_error], JSONSchemer.validate_schema(invalid_draft4_schema, default_schema_class: JSONSchemer::Schema::Draft4).to_a)
    assert_empty(JSONSchemer.validate_schema(valid_detected_draft4_schema).to_a)
    assert_equal([required_error], JSONSchemer.validate_schema(invalid_detected_draft4_schema).to_a)
  end
end

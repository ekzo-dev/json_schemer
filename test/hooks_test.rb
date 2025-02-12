require 'test_helper'

class HooksTest < Minitest::Test
  def test_it_inserts_defaults
    schema = {
      'required' => ['a', 'c', 'd'],
      'properties' => {
        'a' => { 'default' => 1 },
        'b' => { 'default' => 2 },
        'c' => {
          'required' => ['x'],
          'properties' => {
            'x' => { 'default' => 3 },
            'y' => { 'default' => 4 }
          }
        },
        'd' => {
          'required' => ['x'],
          'default' => {
            'x' => {
              'y' => {
                'z' => 1
              }
            }
          },
          'properties' => {
            'x' => {
              'required' => ['y'],
              'properties' => {
                'y' => {
                  'required' => ['z'],
                  'properties' => {
                    'z' => { 'type' => 'integer' }
                  }
                }
              }
            }
          }
        }
      }
    }
    data = {
      'a' => 10,
      'c' => {
        'x' => 30
      }
    }
    refute(JSONSchemer.schema(schema).valid?(data))
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal(
      {
        'a' => 10,
        'b' => 2,
        'c' => {
          'x' => 30,
          'y' => 4
        },
        'd' => {
          'x' => {
            'y' => {
              'z' => 1
            }
          }
        }
      },
      data
    )
  end

  def test_it_does_not_fail_using_insert_defaults_when_no_properties_are_defined_by_schema
    schema = {
      '$comment' => 'Mostly empty schema'
    }
    data = {
      'a' => 1
    }
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal({ 'a' => 1 }, data)
  end

  def test_it_does_not_fail_using_insert_defaults_when_properties_contains_a_boolean_defined_property
    schema = {
      'properties' => {
        'a' => true
      }
    }
    data = {
      'a' => 1
    }
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal({ 'a' => 1 }, data)
  end

  def test_it_does_not_fail_using_insert_defaults_when_properties_contains_a_boolean_defined_property_that_does_not_exist
    schema = {
      'properties' => {
        'b' => true
      }
    }
    data = {
      'a' => 1
    }
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal({ 'a' => 1 }, data)
  end

  def test_it_does_not_insert_defaults_in_conditional_subschemas
    subschema = {
      'properties' => {
        'a' => {
          'const' => 1
        },
        'b' => {
          'const' => 2,
          'default' => 2
        }
      }
    }
    schema = {
      'allOf' => [subschema],
      'anyOf' => [subschema],
      'oneOf' => [subschema],
      'if' => subschema
    }
    data = {
      'a' => 1
    }
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal({ 'a' => 1 }, data)
    refute(JSONSchemer.schema(schema.merge('not' => subschema), insert_property_defaults: true).valid?(data))
    assert_equal({ 'a' => 1 }, data)
  end

  def test_it_calls_before_validation_hooks_to_modify_data
    parse_array = proc do |data, property, property_schema, _|
      if data.key?(property) && property_schema.is_a?(Hash) && property_schema['type'] == 'array'
        parsed = data[property].split(',')
        parsed = parsed.map!(&:to_i) if property_schema['items']['type'] == 'integer'
        data[property] = parsed
      end
    end
    data = { 'list' => '1,2,3', 'list_not_integer' => 'a,b,c', 'other' => 'x' }
    schema = {
      'properties' => {
        'list' => {
          'type' => 'array',
          'items' => { 'type' => 'integer' }
        },
        'list_not_integer' => {
          'type' => 'array',
          'items' => { 'type' => 'string' }
        },
        'other' => {
          'type' => 'string'
        }
      }
    }
    assert(JSONSchemer.schema(
      schema,
      before_property_validation: [parse_array]
    ).valid?(data))
    assert_equal({'list' => [1, 2, 3], 'list_not_integer' => %w[a b c], 'other' => 'x'}, data)
  end

  def test_use_before_validation_hook_to_act_on_parent_schema
    skip_read_only = proc do |data, property, property_schema, schema|
      next unless property_schema['readOnly']
      schema['required'].delete(property)
      if data.key?(property) && property_schema.is_a?(Hash)
        data.delete(property)
      end
    end
    schema = {
      'required' => ['read_only_existing'],
      'properties' => {
        'read_only_existing' => {
          'type' => 'integer',
          'readOnly' => true
        },
        'not_read_only' => {
          'type' => 'string'
        },
        'read_only_missing' => {
          'type' => 'string',
          'readOnly' => true
        }
      }
    }
    schemer = JSONSchemer.schema(
      schema,
      before_property_validation: [skip_read_only]
    )
    data = { 'read_only_existing' => 1, 'not_read_only' => 'x' }
    assert_empty(schemer.validate(data).to_a)
    assert_equal({ 'not_read_only' => 'x' }, data)

    data = {}
    assert_empty(schemer.validate(data).to_a)
    assert_equal({}, data)
  end

  def test_it_accepts_a_single_before_validation_hook_to_modify_data
    parse_array = proc do |data, property, property_schema, _|
      if data.key?(property) && property_schema.is_a?(Hash) && property_schema['type'] == 'array'
        data[property] = data[property].split(',')
        data[property].map!(&:to_i) if property_schema['items']['type'] == 'integer'
      end
    end
    data = { 'list' => '1,2,3', 'list_not_integer' => 'a,b,c', 'other' => 'x' }
    schema = {
      'properties' => {
        'list' => {
          'type' => 'array',
          'items' => { 'type' => 'integer' }
        },
        'list_not_integer' => {
          'type' => 'array',
          'items' => { 'type' => 'string' }
        },
        'other' => {
          'type' => 'string'
        }
      }
    }
    assert(JSONSchemer.schema(
      schema,
      before_property_validation: parse_array
    ).valid?(data))
    assert_equal({'list' => [1, 2, 3], 'list_not_integer' => %w[a b c], 'other' => 'x'}, data)
  end

  def test_it_calls_before_validation_hooks_and_still_inserts_defaults
    replace_fake_with_peter = proc do |data, property, property_schema, _|
      data[property] = 'Peter' if property == 'name' && data[property] == 'fake'
    end
    data = [{ }, { 'name' => 'Bob' }]
    assert(JSONSchemer.schema(
      {
        'type' => 'array',
        'items' => {
          'type' => 'object',
          'properties' => {
            'name' => {
              'type' => 'string',
              'default' => 'fake'
            }
          }
        }
      },
      insert_property_defaults: true,
      before_property_validation: [replace_fake_with_peter]
    ).valid?(data))
    assert_equal([{ 'name' => 'Peter' }, { 'name' => 'Bob' }], data)
  end

  def test_it_calls_after_validation_hooks_to_modify_data
    convert_date = proc do |data, property, property_schema, _|
      if data[property] && property_schema.is_a?(Hash) && property_schema['format'] == 'date'
        data[property] = Date.iso8601(data[property])
      end
    end
    schema = {
      'properties' => {
        'start_date' => {
          'type' => 'string',
          'format' => 'date'
        },
        'email' => {
          'format' => 'email'
        }
      }
    }
    validator= JSONSchemer.schema(
      schema,
      after_property_validation: [convert_date]
    )
    data = { 'start_date' => '2020-09-03', 'email' => 'example@example.com' }
    assert(validator.valid?(data))
    assert_equal({'start_date' => Date.new(2020, 9, 3), 'email' => 'example@example.com'}, data)
  end

  def test_it_accepts_a_single_proc_as_after_validation_hook
    convert_date = proc do |data, property, property_schema|
      if data[property] && property_schema.is_a?(Hash) && property_schema['format'] == 'date'
        data[property] = Date.iso8601(data[property])
      end
    end
    schema = {
      'properties' => {
        'start_date' => {
          'type' => 'string',
          'format' => 'date'
        },
        'email' => {
          'format' => 'email'
        }
      }
    }
    validator= JSONSchemer.schema(
      schema,
      after_property_validation: convert_date
    )
    data = { 'start_date' => '2020-09-03', 'email' => 'example@example.com' }
    assert(validator.valid?(data))
    assert_equal({'start_date' => Date.new(2020, 9, 3), 'email' => 'example@example.com' }, data)
  end

  def test_it_does_not_modify_passed_hooks_array
    schema = {
      'properties' => {
        'list' => {
          'type' => 'array',
          'items' => { 'type' => 'string' }
        }
      }
    }
    data = [{ 'name' => 'Bob' }]
    assert(JSONSchemer.schema(
      schema,
      before_property_validation: [proc {}].freeze,
      after_property_validation: [proc {}].freeze,
      insert_property_defaults: true
    ).valid?(data))
  end
end

{ extend, clone } = require 'lodash'

formatInfo = (definition) ->
  result = {}

  for key, property of definition.properties
    result[key] = clone property

    type = property.type

    if typeof type is 'function'
      type = type.modelName or type.name

    if Array.isArray type
      subtype = type[0]

      if subtype.definition
        subtype = subtype.definition

      type = [ subtype?.modelName or subtype?.name ]

    result[key].type = type

  for key, value of definition.settings.relations
    relation = clone value

    if relation.type in [ 'embedsMany', 'hasMany' ]
      type = [ relation.model ]
    else
      type = relation.model

    if relation.property
      key = relation.property

    result[key] = type: type

  result

_models = {}

module.exports = getModelInfo = (model) ->
  if _models[model.modelName]
    return _models[model.modelName]

  baseModel = undefined
  baseProperties = undefined

  if model.definition.base
    baseModel = getModelInfo model.app.models[model.definition.base]
    baseProperties = formatInfo baseModel.definition

  properties = formatInfo model.definition

  result = extend properties, baseProperties

  _models[model.modelName] = result

  result

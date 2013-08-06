{computed, get, keys, lookup, required} = Ember
{camelize, underscore} = Ember.String

sliceObject = (obj, keys) ->
  ret = {}
  ret[key] = obj[key] for key in keys
  ret

camelizeKeys = (obj) ->
  ret = {}
  ret[camelize(k)] = v for k, v of obj
  ret

underscoreKeys = (obj) ->
  ret = {}
  ret[underscore(k)] = v for k, v of obj
  ret

lookupType = (type) ->
  if typeof(type) == 'string'
    get(lookup, type)
  else
    type

Ember.Thin =
  ajax: (method, url, data = {}) ->
    new Ember.RSVP.Promise (resolve, reject) ->
      data = JSON.stringify(data) unless method == 'GET'

      Ember.$.ajax(
        url:         url
        type:        method
        data:        data
        dataType:    'json'
        contentType: 'application/json; charset=utf-8'
      ).then(resolve, reject)

Ember.Thin.config = config =
  rootUrl: ''

Ember.Thin.Model = Ember.Object.extend Ember.Evented,
  isLoaded: true

  toJSON: ->
    underscoreKeys(@getProperties(keys(@constructor.schema._fields)))

  save: ->
    method = if @get('id') then 'PUT' else 'POST'

    Ember.Thin.ajax(method, @get('_url'), @toJSON()).then @_load.bind(this)

  _load: (json) ->
    camelized = camelizeKeys(json)

    props          = sliceObject(camelized, keys(@constructor.schema._fields))
    props.isLoaded = true

    @setProperties props

    @_loadNestedHasMany   camelized
    @_loadNestedBelongsTo camelized

    do @_wireRelations

    @trigger 'didLoad'

    this

  _loadNestedHasMany: (json) ->
    for name in keys(@constructor.schema._hasManyRelations)
      continue unless array = json[name]

      @get(name).load array

  _loadNestedBelongsTo: (json) ->
    for name, options of @constructor.schema._belongsToRelations
      continue unless obj = json[name]

      lookupType(options.type).load obj
      @set "#{name}Id", obj.id

  _wireRelations: ->
    for name, options of @constructor.schema._belongsToRelations
      continue unless @get("#{name}IsLoaded")
      continue unless @get("#{name}.#{options.inverse}.isLoaded")

      @get("#{name}.#{options.inverse}").pushObject this

  _url: computed(->
    baseUrl = config.rootUrl + @constructor.schema._url

    if id = @get('id')
      [baseUrl, id].join('/')
    else
      baseUrl
  ).property('id')

Ember.Thin.Model.reopenClass
  find: (id) ->
    return model if model = @identityMap[id]

    model = @identityMap[id] = @create(id: id, isLoaded: false)

    Ember.Thin.ajax('GET', model.get('_url')).then model._load.bind(model)

    model

  load: (json) ->
    throw new Error('missing `id` attribute') unless id = json.id

    model = @identityMap[id] = @create() unless model = @identityMap[id]
    model._load(json)

  _setupRelations: ->
    definitions = {}

    for name, options of @schema._hasManyRelations
      definitions[name] = @_getHasMany(name, options)

    for name, options of @schema._belongsToRelations
      definitions[name]            = @_getBelongsTo(name, options)
      definitions["#{name}IsLoaded"] = false

    @reopen definitions

  _getHasMany: (key, options) ->
    computed(->
      type = lookupType(options.type)

      Ember.Thin.HasManyArray.create(
        key:     key
        type:    type
        parent:  this
        options: options
      )
    ).property()

  _getBelongsTo: (key, options) ->
    idName = "#{key}Id"

    computed(->
      type  = lookupType(options.type)
      model = type.find(@get(idName))

      @set "#{key}IsLoaded", true

      model
    ).property(idName)

Ember.Thin.Schema = Ember.Object.extend
  _url: null

  init: ->
    @_super arguments...

    @_fields             = {}
    @_hasManyRelations   = {}
    @_belongsToRelations = {}

  url: (@_url) ->

  field: (name, options = {}) ->
    @_fields[name] = options

  hasMany: (name, options = {}) ->
    @_hasManyRelations[name] = options

  belongsTo: (name, options = {}) ->
    @_belongsToRelations[name] =   options
    @_fields["#{name}Id"]      ||= {}

Ember.Thin.Schema.reopenClass
  define: (block) ->
    schema = @create()

    block.call schema

    type = Ember.Thin.Model.extend()

    type.schema      = schema
    type.identityMap = {}

    do type._setupRelations

    type

Ember.Thin.HasManyArray = Ember.ArrayProxy.extend Ember.Evented,
  key:      required()
  type:     required()
  parent:   required()
  options:  required()
  isLoaded: false
  content:  Ember.A()

  load: (array) ->
    type   = @get('type')
    models = Ember.A(array).map(type.load.bind(type))

    @setProperties
      content:  Ember.A(models)
      isLoaded: true

    @trigger 'didLoad', this

    this

  objectAtContent: ->
    do @fetch unless @get('isLoaded')

    @_super arguments...

  fetch: ->
    Ember.Thin.ajax('GET', @get('url')).then @load.bind(this)

  url: computed(->
    if @get('options.nested')
      [@get('parent._url'), @get('key')].join('/')
    else
      config.rootUrl + @get('type.schema._url')
  ).property()

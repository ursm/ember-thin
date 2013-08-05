{get, keys, required}  = Ember
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
    get(Ember.lookup, type)
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
  toJSON: ->
    underscoreKeys(@getProperties(keys(@constructor.schema._fields)))

  save: ->
    method = if @get('id') then 'PUT' else 'POST'

    Ember.Thin.ajax(method, @get('_url'), @toJSON()).then @_load.bind(this)

  _load: (json) ->
    camelized = camelizeKeys(json)

    @setProperties sliceObject(camelized, keys(@constructor.schema._fields))

    @_loadNestedHasMany   camelized
    @_loadNestedBelongsTo camelized

    do @_wireRelations

    this

  _loadNestedHasMany: (json) ->
    for name in keys(@constructor.schema._hasManyRelations)
      if nested = json[name]
        @get(name).load nested

  _loadNestedBelongsTo: (json) ->
    for name, options of @constructor.schema._belongsToRelations
      if nested = json[name]
        lookupType(options.type).load nested
        @set "#{name}Id", nested.id

  _wireRelations: ->
    for name, options of @constructor.schema._belongsToRelations
      if inverse = @get("#{name}.#{options.inverse}")
        inverse.pushObject this if inverse.get('isLoaded')

  _url: Ember.computed(->
    baseUrl = config.rootUrl + @constructor.schema._url

    if id = @get('id')
      [baseUrl, id].join('/')
    else
      baseUrl
  ).property('id')

Ember.Thin.Model.reopenClass
  find: (id) ->
    @identityMap[id]

  load: (json) ->
    throw new Error('missing `id` attribute') unless id = json.id

    unless model = @identityMap[id]
      model = @identityMap[id] = @create()

    model._load(json)

  _setupRelations: ->
    definitions = {}

    for name, options of @schema._hasManyRelations
      definitions[name] = @_getHasMany(name, options)

    for name, options of @schema._belongsToRelations
      definitions[name] = @_getBelongsTo(name, options)

    @reopen definitions

  _getHasMany: (key, options) ->
    Ember.computed(->
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

    Ember.computed(->
      type = lookupType(options.type)

      type.find(@get(idName))
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

  url: Ember.computed(->
    if @get('options.nested')
      [@get('parent._url'), @get('key')].join('/')
    else
      config.rootUrl + @get('type.schema._url')
  ).property()

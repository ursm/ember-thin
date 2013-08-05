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

  _url: Ember.computed(->
    baseUrl = config.rootUrl + @constructor.schema._url

    if id = @get('id')
      [baseUrl, id].join('/')
    else
      baseUrl
  ).property('id')

  save: ->
    method = if @get('id') then 'PUT' else 'POST'

    Ember.Thin.ajax(method, @get('_url'), @toJSON()).then (json) =>
      @setProperties camelizeKeys(json)

      this

  wireRelations: ->
    for name, options of @constructor.schema._belongsToRelations
      if inverse = @get("#{name}.#{options.inverse}")
        inverse.pushObject this if inverse.get('isLoaded')

lookupType = (type) ->
  if typeof(type) == 'string'
    get(Ember.lookup, type)
  else
    type

Ember.Thin.Model.reopenClass
  find: (id) ->
    @identityMap[id]

  load: (attrs) ->
    throw new Error('missing `id` attribute') unless id = attrs.id

    camelized = camelizeKeys(attrs)

    unless model = @identityMap[id]
      model = @identityMap[id] = @create()

    model.setProperties sliceObject(camelized, keys(@schema._fields))

    for name, options of @schema._hasManyRelations
      if relAttrs = attrs[name]
        model.get(name).load relAttrs

    for name, options of @schema._belongsToRelations
      if relAttrs = attrs[name]
        lookupType(options.type).load relAttrs
        model.set "#{name}Id", relAttrs.id

    do model.wireRelations

    model

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
    Ember.computed(->
      type = lookupType(options.type)

      type.find(@get("#{key}Id"))
    ).property()

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
      isLoaded: true
      content:  Ember.A(models)

  objectAtContent: ->
    do @fetch unless @get('isLoaded')

    @_super arguments...

  fetch: ->
    Ember.Thin.ajax('GET', @get('url')).then (models) =>
      @setProperties
        content:  Ember.A(models)
        isLoaded: true

      @trigger 'load', this

  url: Ember.computed(->
    if @get('options.nested')
      [@get('parent._url'), @get('key')].join('/')
    else
      config.rootUrl + @get('type.schema._url')
  ).property()

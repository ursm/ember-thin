assert = require('assert')
sinon  = require('sinon')

global.ENV =
  EXTEND_PROTOTYPES: false

require './vendor/ember-runtime'
require '../lib/ember-thin'

beforeEach ->
  @sinon = sinon.sandbox.create()

  @stubAjax = (returns) =>
    promise = new Ember.RSVP.Promise (resolve, reject) ->
      resolve returns

    @sinon.stub(Ember.Thin, 'ajax').returns promise

afterEach ->
  do @sinon.restore

Ember.Thin.config.rootUrl = '/api'

global.App = Ember.Application.create()

App.Organization = Ember.Thin.Model.define ->
  @url '/organizations'

  @field 'name'
  @field 'slug'

  @hasMany 'users', type: 'App.User', inverse: 'organizations', nested: true
  @hasMany 'rooms', type: 'App.Room', inverse: 'organization',  nested: true

App.User = Ember.Thin.Model.define ->
  @url '/users'

  @field 'name'

  @hasMany 'rooms', type: 'App.Room', inverse: 'members', nested: true

App.Room = Ember.Thin.Model.define ->
  @url '/rooms'

  @field 'name'

  @hasMany 'members', type: 'App.User', inverse: 'rooms', nested: true

describe 'Ember.Thin', ->
  describe '.toJSON', ->
    it 'should convert to an object', ->
      org = App.Organization.create(name: 'Foo', slug: 'foo')

      assert.deepEqual org.toJSON(), name: 'Foo', slug: 'foo'

  describe '._url', ->
    beforeEach ->
      @org = App.Organization.create()

    context 'have ID', ->
      it 'should contain ID within URL', ->
        @org.set 'id', 42

        assert.equal @org.get('_url'), '/api/organizations/42'

    context 'do not have ID', ->
      it 'should not contain ID within URL', ->
        @org.set 'id', null

        assert.equal @org.get('_url'), '/api/organizations'

  describe 'has many relation', ->
    it 'should be kind of HasManyArray', ->
      org = App.Organization.create(id: 42)

      assert.equal org.get('users').constructor, Ember.Thin.HasManyArray

    describe '._url', ->
      beforeEach ->
        @org = App.Organization.create(id: 42)

      context 'nested resource', ->
        it 'should return nested URL', ->
          assert.equal @org.get('users._url'), '/api/organizations/42/users'

    describe '.fetch', ->
      beforeEach ->
        @stubAjax
          users: [
            {id: 1}
            {id: 2}
            {id: 3}
          ]

      it 'should fetch records', (done) ->
        org = App.Organization.create(id: 42)

        org.get('users').fetch().then (users) ->
          assert.equal users.get('length'), 3
          do done

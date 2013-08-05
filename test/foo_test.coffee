assert = require('assert')
sinon  = require('sinon')

global.ENV =
  EXTEND_PROTOTYPES: false

require './vendor/ember-runtime'
require '../lib/ember-thin'

beforeEach ->
  @sinon = sinon.sandbox.create()

  @stubAjax = (method, url, returns) =>
    promise = new Ember.RSVP.Promise (resolve, reject) ->
      resolve returns

    @sinon.stub(Ember.Thin, 'ajax').withArgs(method, url).returns promise

afterEach ->
  do @sinon.restore

beforeEach ->
  Ember.Thin.ajax = -> throw new Error('must stub it')

  Ember.Thin.config.rootUrl = '/api'

  global.App = Ember.Application.create()

  App.Organization = Ember.Thin.Schema.define ->
    @url '/organizations'

    @field 'id'

    @hasMany 'members', type: 'App.User', inverse: 'organization', nested: true

  App.User = Ember.Thin.Schema.define ->
    @url '/users'

    @field 'id'
    @field 'name'
    @field 'realName'

    @belongsTo 'organization', type: 'App.Organization', inverse: 'members'
    @hasMany   'rooms',        type: 'App.Room',         inverse: 'members', nested: true

  App.Room = Ember.Thin.Schema.define ->
    @url '/rooms'

    @field 'id'

    @hasMany 'members', type: 'App.User', inverse: 'rooms', nested: true

describe 'Ember.Thin', ->
  describe '.load', ->
    it 'should load a record', ->
      user = App.User.load(id: 42, real_name: 'foo')

      assert.equal user.get('id'),       42
      assert.equal user.get('realName'), 'foo'

    context 'twice', ->
      it 'should update a record', ->
        one = App.User.load(id: 42, name: 'foo')
        two = App.User.load(id: 42, name: 'bar')

        assert.equal one, two
        assert.equal two.get('name'), 'bar'

  describe '.toJSON', ->
    it 'should convert to an object', ->
      user = App.User.load(id: 42, name: 'ursm', real_name: 'Keita Urashima')

      assert.deepEqual user.toJSON(), id: 42, name: 'ursm', real_name: 'Keita Urashima'

  describe '.save', ->
    beforeEach ->
      @user = App.User.create()

    context 'when record is unsaved', ->
      beforeEach ->
        @stubAjax 'POST', '/api/users', id: 42

      it 'should post data', (done) ->
        @user.save().then (user) =>
          assert.equal user, @user
          assert.equal user.get('id'), 42
          do done

    context 'when record is saved', ->
      beforeEach ->
        @user.set 'id', 42

        @stubAjax 'PUT', '/api/users/42', id: 42, name: 'ursm'

      it 'should post data', (done) ->
        @user.save().then (user) =>
          assert.equal user, @user
          assert.equal user.get('name'), 'ursm'
          do done

  describe '._url', ->
    beforeEach ->
      @user = App.User.create()

    context 'have ID', ->
      it 'should contain ID within URL', ->
        @user.set 'id', 42

        assert.equal @user.get('_url'), '/api/users/42'

    context 'do not have ID', ->
      it 'should not contain ID within URL', ->
        @user.set 'id', null

        assert.equal @user.get('_url'), '/api/users'

  describe 'one-to-many relation', ->
    describe '.load', ->
      it 'should load records', ->
        org     = App.Organization.load(id: 42)
        members = org.get('members')

        assert.ok    !members.get('isLoaded')
        assert.equal members.get('length'), 0

        members.load [
          {id: 1}
          {id: 2}
        ]

        assert.ok    members.get('isLoaded')
        assert.equal members.get('length'), 2
        assert.equal members.get('firstObject').constructor, App.User

      it 'should get parent model', ->
        org     = App.Organization.load(id: 42)
        members = org.get('members')

        assert.equal members.get('parent'), org

    describe '.url', ->
      beforeEach ->
        @org = App.Organization.load(id: 42)

      context 'nested resource', ->
        it 'should return nested URL', ->
          assert.equal @org.get('members.url'), '/api/organizations/42/members'

    context 'get unloaded relation', ->
      beforeEach ->
        @stubAjax 'GET', '/api/organizations/42/members', [
          {id: 1}
          {id: 2}
          {id: 3}
        ]

      it 'should fetch records', (done) ->
        org = App.Organization.load(id: 42)

        org.get('members').on 'load', (members) ->
          assert.ok    members.get('isLoaded')
          assert.equal members.get('length'), 3
          do done

        # trigger 'load'
        org.get('members.firstObject')

  describe 'belongsTo relation', ->
    beforeEach ->
      @org = App.Organization.load(id: 42)

    context 'when inverse relation is loaded', ->
      beforeEach ->
        do @org.get('members').load

      it 'should be automatically wired', ->
        user = App.User.load(id: 1, organization_id: 42)

        assert.equal user.get('organization'), @org
        assert.ok    @org.get('members').contains(user)

    context 'when inverse relation is not loaded', ->
      it 'should do nothing', ->
        user = App.User.load(id: 1, organization_id: 42)

        assert.equal user.get('organization'), @org
        assert.ok    !@org.get('members.isLoaded')

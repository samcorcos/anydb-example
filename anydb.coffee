if Meteor.isServer
  # Instantiates a new Neo4j object
  @Neo4j = new Neo4jDB("http://neo4j_test:QjCTKSXHFKMezZc40Say@neo4jtest.sb05.stations.graphenedb.com:24789")

  DB.publish
    name: 'messages'

    # Creates the query to find all messages with
    # the current roomId
    query: (roomId) -> Neo4j.query """
      MATCH (a:#{roomId})
      RETURN a
      """

    # Sets a dependency on the chatroom's roomId
    depends: (roomId) -> ["chatroom:#{roomId}"]

if Meteor.isClient
  # Creates a subscription for messages and passes in roomId
  messages = DB.createSubscription('messages', roomId)

  Template.main.onRendered ->
    messages.start()

  Template.main.onDestroyed ->
    messages.stop()

  Template.main.helpers
    messages: -> messages

  Template.main.events
    'click #submit': (e,t) ->
      input = t.find('input')
      # We need to create a new hex string as the _id
      msgId = DB.newId()
      Meteor.call 'newMsg', roomId, msgId, input.value, (err,res) ->
        # In the event of an error, remove the message
        # from the client
        if err then messages.handleUndo(msgId)
      input.value = ''
    'keyup input': (e,t) ->
      if e.keyCode is 13
        input = t.find('input')
        # We need to create a new hex string as the _id
        msgId = DB.newId()
        Meteor.call 'newMsg', roomId, msgId, input.value, (err,res) ->
          # In the event of an error, remove the message
          # from the client
          if err then messages.handleUndo(msgId)
        input.value = ''
    'click #reset': (e,t) ->
      Neo4j.reset()



Meteor.methods
  newMsg: (roomId, msgId, text) ->
    if Meteor.isServer
      # Creates the new message in the database
      Neo4j.query """
        CREATE (:#{roomId} {
          text:#{Neo4j.stringify(text)},
          _id:#{msgId} }
        """
      # When the new message is created,
      # trigger the dependencies of that item
      DB.triggerDeps("chatroom:#{roomId}")
    else
      # Everything below is for latency compensation
      # and can be omitted
      fields = {_id: msgId, text: text, unverified: true}
      before = messages.docs[0]?._id or null
      messages.addedBefore(msgId, fields, before)
      undo = -> messages.removed(msgId)
      messages.addUndo(msgId, undo)

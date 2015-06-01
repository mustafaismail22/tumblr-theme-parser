{parse} = require './parser'
cheerio = require 'cheerio'
clone = require 'lodash.clone'

transformKeysRecursive = (obj, fn) ->
  output = {}
  for i of obj
    if Object::toString.apply(obj[i]) is '[object Object]'
      output[fn(i)] = transformKeysRecursive(obj[i], fn)
    else if Array.isArray(obj[i])
      output[fn(i)] = []
      for e in obj[i]
        output[fn(i)].push transformKeysRecursive(e, fn)
    else
      output[fn(i)] = obj[i]
  output

compile = (text, data = {}) ->
  data = clone(data) # we're going to mutate it w/ info from meta tags
  $ = cheerio.load(text)
  metaTags = $('meta')
  for tag in metaTags
    key = $(tag).attr('name')
    v = $(tag).attr('content')

    if not key? or data[key]? then continue

    if key[0...3] is 'if:'
      if v is '0'
        v = false
      else if v is '1'
        v = true

    data[key] = v

  # fix up tumblr data
  if data?['block:Posts']?
    for post in data['block:Posts']
      type = post['PostType']
      post["block:#{type}"] = true

  data = transformKeysRecursive(data, (key) ->
    # handle case insensitivity (matches the transformation applied to the AST)
    key = key.toLowerCase()

    if key[0...3] is 'if:'
      # if blocks don't have spaces (probably because they're blocks)
      key = key.replace(/\s/g, '')

    return key
  )

  compileBlock = (ast, data, searchParentScope) ->
    searchScope = (type, tagName) ->
      key = (
        if type is ''
          tagName
        else
          "#{type}:#{tagName}"
      )
      value = data[key]

      # if blocks can reference variables (which may have spaces in them), so we
      # need to check all the vars if we still didn't find it
      if not value? and type is 'if'
        for key in Object.keys(data)
          if tagName is key.replace(/\s/g, '').replace(/^[a-z]+:/, '')
            value = data[key]
            break

      if not value? and searchParentScope?
        value = searchParentScope(type, tagName)
      return value

    compileElement = (element) ->
      if typeof element is 'string'
        return element
      else if element.type isnt 'block'
        value = searchScope(element.type, element.tagName)
        if value?
          return value
        else
          console.warn "Variable \"#{key}\" is undefined"
          return ''
      else
        [blockType, blockName, invert] = (
          if element.tagName[0...5] is 'ifnot'
            ['if', "#{element.tagName[5...]}", true]
          else if element.tagName[0...2] is 'if'
            ['if', "#{element.tagName[2...]}", false]
          else
            ['block', "#{element.tagName}", false]
        )
        value = searchScope(blockType, blockName)

        if blockType is 'if'
          if value? and value isnt ''
            if typeof value isnt 'boolean' then value = true
          else
            # if it still doesn't exist, then the if block is false
            value = false

          if invert then value = not value

        if typeof value is 'boolean' and value
          # process children in current context
          return compileBlock(element.contents, data, searchScope)
        else if Array.isArray(value)
          # process the contents of the element in each supplied context
          out = ''
          for context in value
            out += compileBlock(element.contents, context, searchScope)
          return out
        else if typeof value is 'object'
          # process the contents of the element in the supplied context
          return compileBlock(element.contents, value, searchScope)
        else
          # if value is falsey or undefined then we just discard the children
          return ''

    output = ''
    for element in ast
      output += compileElement(element)
    return output

  ast = parse(text)
  result = compileBlock(ast, data).split('\n')

  # remove trailing whitespace
  for i in [0...result.length]
    result[i] = result[i].trimRight()

  # filter multiple sequential linebreaks
  result = result.filter (val, i, arr) -> not (val is '' and arr[i - 1] is '')

  return result.join('\n')

module.exports = {compile, parse}

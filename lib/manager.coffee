{ Disposable } = require 'atom'
fs = require 'fs'
path = require 'path'

module.exports =
class Manager extends Disposable
  constructor: (latex) ->
    @latex = latex

  findMain: ->
    if @latex.mainFile != undefined
      return true

    docRegex = /\\begin{document}/
    editor = atom.workspace.getActivePaneItem()
    currentPath = editor?buffer.file?.path
    currentContent = editor?.getText()

    if currentPath and currentContent
      if ((path.extname currentPath) == '.tex') and
          (currentContent.match docRegex)
        @latex.mainFile = currentPath
        return true

    for rootDir in atom.project.getPaths()
      for file in fs.readdirSync rootDir
        if (path.extname file) != '.tex'
          continue
        filePath = path.join rootDir, file
        fileContent = fs.readFileSync filePath, 'utf-8'
        if fileContent.match docRegex
          @latex.mainFile = filePath
          return true
    return false

  findAll: ->
    if !@findMain()
      return false
    @latex.texFiles = [ @latex.mainFile ]
    @latex.bibFiles = []
    @findDependentFiles(@latex.mainFile)

  findDependentFiles: (file) ->
    content = fs.readFileSync file, 'utf-8'
    baseDir = path.dirname(@latex.mainFile)
    
    inputReg = /(?:\\input(?:\[[^\[\]\{\}]*\])?){([^}]*)}/g
    loop
      result = inputReg.exec content
      break if !result?
      inputFile = result[1]
      if path.extname(inputFile) is ''
        inputFile += '.tex'
      filePath = path.resolve(path.join(baseDir, inputFile))
      if @latex.texFiles.indexOf(filePath) < 0
        @latex.texFiles.push(filePath)
        @findDependentFiles(filePath)

    bibReg = /(?:\\bibliography(?:\[[^\[\]\{\}]*\])?){([\w\d\s,]+)}/g
    loop
      result = bibReg.exec content
      break if !result?
      bibs = result[1].split(',').map((bib) -> bib.trim())
      paths = bibs.map((bib) =>
        if path.extname(bib) is ''
          bib += '.bib'
        bib = path.resolve(path.join(baseDir, bib))
        if @latex.bibFiles.indexOf(bib) < 0
          @latex.bibFiles.push(bib)
      )
    return true

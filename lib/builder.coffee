{ Disposable } = require 'atom'
path = require 'path'
cp = require 'child_process'
hb = require 'hasbin'

module.exports =
class Builder extends Disposable
  constructor: (latex) ->
    @latex = latex

  build: (here) ->
    if !@latex.manager.findMain(here)
      return false

    @killProcess()
    @setCmds()
    @latex.logger.log = []
    @latex.panel.view.showLog = true
    @buildLogs = []
    @execCmds = []
    @buildProcess()

    return true

  execCmd: (cmd, env, cb) ->
    return cp.exec(cmd, env, cb)

  buildProcess: ->
    cmd = @cmds.shift()
    if cmd == undefined
      @postBuild()
      return

    @buildLogs.push ''
    @execCmds.push cmd
    @latex.logPanel.showText icon: 'sync', spin: true, 'Building LaTeX.'
    @latex.logPanel.addStepLog(@buildLogs.length, cmd)
    @process = @execCmd(
      cmd, {cwd: path.dirname @latex.mainFile}, (err, stdout, stderr) =>
        @process = undefined
        if !err
          @buildProcess()
        else
          @latex.logger.processError(
            """Failed Building LaTeX (code #{err.code}).""", err.message, true,
            [{
              text: "Show build log"
              onDidClick: => @latex.logPanel.showLog()
            }]
          )
          @cmds = []
          @latex.parser.parse @buildLogs?[@buildLogs?.length - 1]
          @latex.logPanel.showText icon: @latex.parser.status, 'Error.', 3000
          @latex.logPanel.addPlainLog 'Error occurred while building LaTeX.'
    )

    @process.stdout.on 'data', (data) =>
      @buildLogs[@buildLogs.length - 1] += data

  postBuild: ->
    @latex.parser.parse @buildLogs?[@buildLogs?.length - 1]
    @latex.logger.clearBuildError()
    @latex.logPanel.addPlainLog 'Successfully built LaTeX.'
    @latex.logPanel.showText icon: @latex.parser.status, 'Success.', 3000
    if @latex.viewer.client.ws?
      @latex.viewer.refresh()
    else if atom.config.get('atom-latex.preview_after_build') isnt\
        'Do nothing'
      @latex.viewer.openViewer()

  killProcess: ->
    @cmds = []
    @process?.kill()

  binCheck: (binary) ->
    if hb.sync binary
      return true
    return false

  setCmds: ->
    if atom.config.get('atom-latex.toolchain') == 'auto'
      if !@latexmk_toolchain()
        @custom_toolchain()
    else if atom.config.get('atom-latex.toolchain') == 'latexmk toolchain'
      @latexmk_toolchain()
    else if atom.config.get('atom-latex.toolchain') == 'custom toolchain'
      @custom_toolchain()

  latexmk_toolchain: ->
    @cmds = [
      """latexmk \
      #{atom.config.get('atom-latex.latexmk_param')} \
      #{path.basename(@latex.mainFile, '.tex')}"""
    ]
    if !@binCheck('latexmk') or !@binCheck('perl')
      return false
    return true

  custom_toolchain: ->
    texCompiler = atom.config.get('atom-latex.compiler')
    bibCompiler = atom.config.get('atom-latex.bibtex')
    args = atom.config.get('atom-latex.compiler_param')
    toolchain = atom.config.get('atom-latex.custom_toolchain').split('&&')
    toolchain = toolchain.map((cmd) -> cmd.trim())
    @cmds = []
    result = []
    for toolPrototype in toolchain
      cmd = toolPrototype
      cmd = cmd.split('%TEX').join(texCompiler)
      cmd = cmd.split('%BIB').join(bibCompiler)
      cmd = cmd.split('%ARG').join(args)
      cmd = cmd.split('%DOC').join(path.basename(@latex.mainFile, '.tex'))
      @cmds.push cmd

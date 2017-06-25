require 'pathname'
require 'fileutils'
include FileUtils

QtVersionString = ENV.fetch('version')
QtVersionMajor = QtVersionString.split('.').first.to_i

def parse_prl_file(filename)
  attrs = { prl_filename: Pathname(filename) }
  File.foreach(filename) do |line|
    md = line.match(/(\w+) = (.*)/)
    attrs[md[1]] = md[2]
  end
  attrs
end

def libs_from_prl(prl)
  libs = []

  target = prl.fetch('QMAKE_PRL_TARGET')
  if !Pathname(target).absolute?
    libs << "-L#{prl.fetch(:prl_filename).dirname}"
  end
  if md = target.match(/lib(\w+).a/)
    libs << target
  end

  listed_libs = prl.fetch('QMAKE_PRL_LIBS')
  listed_libs.gsub!(/\$\$\[QT_INSTALL_LIBS\]/, (OutDir + 'lib').to_s)
  libs.concat listed_libs.split(' ')

  libs
end

QtBaseDir = Pathname(ENV.fetch('qtbase'))
OutDir = Pathname(ENV.fetch('out'))

puts
puts "qtbase: #{QtBaseDir}"
puts "out: #{OutDir}"
puts

mkdir OutDir
symlink QtBaseDir + 'include', OutDir + 'include'
symlink QtBaseDir + 'bin', OutDir + 'bin'
symlink QtBaseDir + 'plugins', OutDir + 'plugins'

mkdir OutDir + 'lib'

(QtBaseDir + 'lib').each_child do |c|
  if %w(.a .prl).include?(c.extname)
    symlink c, OutDir + 'lib'
  end
end

CMakeDir = OutDir + 'lib' + 'cmake'
mkdir CMakeDir

mkdir CMakeDir + 'Qt5Widgets'

File.open(CMakeDir + 'core.cmake', 'w') do |f|
  f.puts "set(QT_VERSION_MAJOR #{QtVersionMajor})"
  f.puts

  moc_exe = OutDir + 'bin' + 'moc'
  f.puts "add_executable(Qt5::moc IMPORTED)"
  f.puts "set(QT_MOC_EXECUTABLE #{moc_exe})"
  f.puts "set_target_properties(Qt5::moc PROPERTIES " \
         "IMPORTED_LOCATION ${QT_MOC_EXECUTABLE})"
end

File.open(CMakeDir + 'Qt5Widgets' + 'Qt5WidgetsConfig.cmake', 'w') do |f|
  afile = OutDir + 'lib' + 'libQt5Widgets.a'

  includes = [
    QtBaseDir + 'include',
    QtBaseDir + 'include' + 'QtWidgets',
    QtBaseDir + 'include' + 'QtCore',
    QtBaseDir + 'include' + 'QtGui',
  ]

  libs = [ OutDir + 'lib' + 'libQt5Core.a' ]
  prls = [
    OutDir + 'lib' + 'Qt5Widgets.prl',
    OutDir + 'plugins' + 'platforms' + 'qwindows.prl',
    OutDir + 'lib' + 'Qt5Gui.prl',
    OutDir + 'lib' + 'Qt5Core.prl',
  ]
  prls.each do |prl|
    prl_libs = libs_from_prl(parse_prl_file(prl))
    libs.concat(prl_libs)
  end

  properties = {
    IMPORTED_LOCATION: afile,
    IMPORTED_LINK_INTERFACE_LANGUAGES: 'CXX',
    IMPORTED_LINK_INTERFACE_LIBRARIES: libs.join(' '),
    INTERFACE_INCLUDE_DIRECTORIES: includes.join(' '),
    INTERFACE_COMPILE_DEFINITIONS: 'QT_STATIC',
  }

  f.puts "add_library(Qt5::Widgets STATIC IMPORTED)"
  properties.each do |name, value|
    f.puts "set_property(TARGET Qt5::Widgets PROPERTY #{name} #{value})"
  end

  f.puts "include(#{CMakeDir + 'core.cmake'})"
end
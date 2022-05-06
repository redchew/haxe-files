/*
 * Copyright (c) 2016-2022 Vegard IT GmbH (https://vegardit.com) and contributors.
 * SPDX-License-Identifier: Apache-2.0
 */
package hx.files;

import hx.files.internal.OS;
import hx.strings.internal.Either2;

#if (sys || macro || nodejs)
import sys.FileSystem;
#end

#if java
import java.lang.System;
#elseif cs
import cs.system.Environment;
import cs.system.Environment.Environment_SpecialFolder;
#end

using hx.strings.Strings;

/**
 * Represents a directory.
 *
 * @author Sebastian Thomschke, Vegard IT GmbH
 */
class Dir {

   #if (filesystem_support || macro)

   /**
    * <pre><code>
    * >>> Dir.getCWD().path.exists()      == true
    * >>> Dir.getCWD().path.isDirectory() == true
    * </code></pre>
    *
    * @return the current working directory
    */
   public static function getCWD():Dir {
      #if (sys || nodejs)
         return of(Sys.getCwd());
      #elseif (phantomjs && !macro)
         return of(js.phantomjs.FileSystem.workingDirectory);
      #else
         throw "Operation not supported on current target.";
      #end
   }


   /**
    * <pre><code>
    * >>> Dir.getUserHome().path.exists()      == true
    * >>> Dir.getUserHome().path.isDirectory() == true
    * </code></pre>
    *
    * @return the user's home directory
    */
   public static function getUserHome():Dir {
      #if cs
         #if (net_ver < 40)
            if (Environment.OSVersion.Platform == cs.system.PlatformID.Unix || Environment.OSVersion.Platform == cs.system.PlatformID.MacOSX)
               return Dir.of(Environment.GetEnvironmentVariable("HOME"));
            return Dir.of(Environment.ExpandEnvironmentVariables("%HOMEDRIVE%%HOMEPATH%"));
         #else
            return Dir.of(Environment.GetFolderPath(Environment_SpecialFolder.UserProfile));
         #end
      #elseif java
         return Dir.of(System.getProperty("user.home"));
      #elseif python
         return Dir.of(python.lib.os.Path.expanduser("~"));
      #elseif (phantomjs && !macro)
         untyped __js__("var system = require('system');");
         if (OS.isWindows)
            return Dir.of("" + untyped __js__("system.env['HOMEDRIVE']") + untyped __js__("system.env['HOMEPATH']"));
         return Dir.of("" + untyped __js__("system.env['HOME']"));
      #elseif (sys || nodejs)
         if (OS.isWindows)
            #if nodejs @:nullSafety(Off) #end
            return Dir.of(Sys.getEnv("HOMEDRIVE") + Sys.getEnv("HOMEPATH"));
         #if nodejs @:nullSafety(Off) #end
         return Dir.of(Sys.getEnv("HOME"));
      #else
         throw "Operation not supported on current target.";
      #end
   }

   #end // (filesystem_support || macro)

   /**
    * This method does not check if the path actually exists and if it currently points to a directory or a file
    *
    * <pre><code>
    * >>> Dir.of(null) throws "[path] must not be null"
    * </code></pre>
    *
    * @param trimWhiteSpaces controls if leading/trailing whitespaces of path elements shall be removed automatically
    */
   public static function of(path:Either2<String, Path>, trimWhiteSpaces = true):Dir {
      if (path == null)
         throw "[path] must not be null";

      return switch(path.value) {
         case a(str): new Dir(Path.of(str, trimWhiteSpaces));
         case b(obj): new Dir(obj);
      }
   }


   public final path:Path;


   inline
   function new(path:Path) {
      this.path = path;
   }

   #if (filesystem_support || macro)

   function assertValidPath(mustExist = true) {
      if (path.filename.isEmpty())
         throw "[path.filename] must not be null or empty!";

      if (path.exists()) {
         if (!path.isDirectory()) throw '[path] "$path" exists but is not a directory!';
      } else {
         if (mustExist) throw '[path] "$path" does not exist!';
      }
   }


   /**
    * Creates the given directory incl. all parent directories in case they don't exist yet
    *
    * <pre><code>
    * >>> Dir.of("target/foo/bar/dog").create() throws nothing
    * >>> Dir.of("target/foo/bar"    ).create() == false
    * >>> Dir.of("README.md"         ).create() throws '[path] "README.md" exists but is not a directory!'
    * </code></pre>
    *
    * @return true if dir was created, false if exists already
    * @throws if path is not a directory
    */
   public function create():Bool {

      assertValidPath(false);

      if (path.exists())
         return false;

      #if lua
         // workaround for https://github.com/HaxeFoundation/haxe/issues/6946
         final parts = [ path ];
         final _p = path;
         while ((_p = _p.parent) != null) {
            if (_p.isRoot)
               break;
            parts.insert(0, _p);
         }

         for (_p in parts) {
            if (!_p.exists() && !lua.lib.luv.fs.FileSystem.mkdir(_p.toString(), 511 ).result)
               throw 'Could not create directory: $_p';
         }
         return true;
      #elseif (sys || macro || nodejs)
         FileSystem.createDirectory(path.toString());
         return true;
      #elseif phantomjs
         js.phantomjs.FileSystem.makeTree(path.toString());
         return true;
      #else
         throw "Operation not supported on current target.";
      #end
   }


   /**
    * Recursively copies the given directory.
    *
    * <pre><code>
    * >>> Dir.of("target/copyA/11").create()            throws nothing
    * >>> File.of("target/copyA/11/test.txt").touch()   throws nothing
    *
    * >>> Dir.of("target/copyA").copyTo("target/copyB")              throws nothing
    * >>> File.of("target/copyB/11/test.txt").path.exists()          == true
    * >>> Dir.of("target/copyA").copyTo("target/copyB")              throws '[newPath] "target' + Path.of("").dirSep + 'copyB" already exists!'
    * >>> Dir.of("target/copyA").copyTo("target/copyB", [OVERWRITE]) throws nothing
    * >>> Dir.of("target/copyA").copyTo("target/copyB", [MERGE])     throws nothing
    *
    * >>> Dir.of("target/copyA").delete(true)           throws nothing
    * >>> Dir.of("target/copyB").delete(true)           throws nothing
    * </code></pre>
    *
    * @return a Dir instance pointing to the copy target
    */
   public function copyTo(newPath:Either2<String, Path>, ?options:Array<DirCopyOption>):Dir {
      assertValidPath();

      if (newPath == null)
         throw "[newPath] must not be null or empty!";

      var trimWhiteSpaces = true;
      var overwrite = false;
      var merge = false;
      var onFile:Null<(File, File) -> Void> = null;
      var onDir:Null<(Dir, Dir) -> Void> = null;

      if (options != null) for (o in options) {
         switch(o) {
            case OVERWRITE: overwrite = true;
            case MERGE: merge = true;
            case NO_WHITESPACE_TRIMMING: trimWhiteSpaces = false;
            case LISTENER(f, d): onFile = f; onDir = d;
         }
      }

      final targetPath:Path = switch(newPath.value) {
         case a(str): Path.of(str, trimWhiteSpaces);
         case b(obj): obj;
      }

      if (targetPath.filename == "")
         throw "[newPath] must not be null or empty!";

      if (path.getAbsolutePath() == targetPath.getAbsolutePath())
         return this;

      final targetDir = targetPath.toDir();

      if (targetPath.exists()) {
         if (!overwrite && !merge)
            throw '[newPath] "$targetPath" already exists!';

         if (!targetPath.isDirectory())
            throw '[newPath] "$targetPath" already exists and is not a directory!';

         if(!merge)
            targetDir.delete(true);
      }

      #if (sys || macro || nodejs || phantomjs)
         #if (phantomjs && !macro)
            if (!merge) {
               js.phantomjs.FileSystem.copyTree(path.toString(), targetPath.toString());
               return targetDir;
            }
         #end
         final sourcPathLen = toString().length;
         targetDir.create();
         walk(
            function(file) {
               final targetDirFile = targetDir.path.join(file.path.toString().substr(sourcPathLen)).toFile();
               file.copyTo(targetDirFile.path, merge ? [OVERWRITE] : null);
               if (onFile != null) onFile(file, targetDirFile);
            },
            function(dir) {
               final targetDirDir = targetDir.path.join(dir.path.toString().substr(sourcPathLen)).toDir();
               targetDirDir.create();
               if (onDir != null) onDir(dir, targetDirDir);
               return true;
            }
         );
         return targetDir;
      #else
         throw "Operation not supported on current target.";
      #end
   }


   public function isEmpty() {
      assertValidPath(false);

      if (!path.exists())
         return true;

      #if (sys || macro || nodejs)
         return FileSystem.readDirectory(path.toString()).length == 0;
      #elseif phantomjs
         return [for (entry in js.phantomjs.FileSystem.list(path.toString())) if (entry != "." && entry != "..") entry].length == 0;
      #else
         throw "Operation not supported on current target.";
      #end
   }


   /**
    * Recursively deletes the given directory.
    *
    * <pre><code>
    * >>> Dir.of(""         ).delete() == false
    * >>> Dir.of("README.md").delete() throws '[path] "README.md" exists but is not a directory!'
    *
    * >>> Dir.of("target/foo/bar/dog").create() throws nothing
    * >>> File.of("target/foo/bar/dog/test.txt").writeString("test") throws nothing
    * >>> Dir.of("target/foo").delete()         throws 'Cannot delete directory "target' + Path.of("").dirSep + 'foo" because it is not empty!'
    * >>> Dir.of("target/foo").delete(true)     == true
    * >>> Dir.of("target/foo").delete()         == false
    *
    * <code></pre>
    *
    * @return false if path does not exist
    *
    * @throws if path is not a directory
    */
   public function delete(recursively = false):Bool {

      if (!path.exists())
         return false;

      assertValidPath();

      if (!recursively && !isEmpty())
         throw 'Cannot delete directory "$path" because it is not empty!';

      #if (phantomjs && !macro)
         js.phantomjs.FileSystem.removeTree(path.toString());
      #elseif (sys || nodejs)
         final dirs:Array<Dir> = [];
         walk(
            file -> file.delete(),
            dir  -> { dirs.push(dir); return true; }
         );
         dirs.reverse();
         dirs.push(this);
         for (dir in dirs)
            FileSystem.deleteDirectory(dir.path.toString());
      #else
          throw "Operation not supported on current target.";
      #end
      return true;

   }


   /**
    * @param globPattern Pattern in the Glob syntax style, see https://docs.oracle.com/javase/tutorial/essential/io/fileOps.html#glob
    */
   public function find(globPattern:String, onFileMatch:Null<File -> Void>, onDirMatch:Null<Dir -> Void>) {

      if (!path.exists())
         return;

      assertValidPath();

      final p = path.toString();
      final searchRootPath = p + globPattern.substringBefore("*").substringBeforeLast("/");
      final filePattern = GlobPatterns.toEReg(globPattern);
      final searchRootOffset = p.endsWith(path.dirSep) ? p.length8() : p.length8() + 1;

      Dir.of(searchRootPath).walk(
         function(file) {
            #if python @:nullSafety(Off) #end
            if (filePattern.match(file.path.toString().substr8(searchRootOffset))) {
               if (onFileMatch != null) onFileMatch(file);
            }
         },
         function(dir) {
            #if python @:nullSafety(Off) #end
            if (filePattern.match(dir.path.toString().substr8(searchRootOffset))) {
               if (onDirMatch != null) onDirMatch(dir);
            }
            return true;
         }
      );
   }


   /**
    * <pre><code>
    * >>> [ for (d in Dir.of(".").findDirs("*"           )) d.path.filename ].indexOf("src")   > -1
    * >>> [ for (d in Dir.of(".").findDirs("*" + "/hx/f*")) d.path.filename ].indexOf("files") > -1
    * >>> [ for (d in Dir.of(".").findDirs("**" + "/fi*" )) d.path.filename ].indexOf("files") > -1
    *
    * >>> [ for (d in Dir.of(".").findFiles("*"           )) d.path.filename ].indexOf("README.md") >  -1
    * >>> [ for (d in Dir.of(".").findFiles("**" + "/*.hx")) d.path.filename ].indexOf("Dir.hx")    >  -1
    * >>> [ for (d in Dir.of(".").findFiles("*"  + "/*.hx")) d.path.filename ].indexOf("Dir.hx")    == -1
    *
    * >>> Dir.of(""  ).findDirs("*").length  == 0
    * </code></pre>
    */
   public function findDirs(globPattern:String):Array<Dir> {
      final dirs = new Array<Dir>();
      find(globPattern, null, dir -> dirs.push(dir));
      return dirs;
   }


   /**
    * <pre><code>
    * >>> [ for (f in Dir.of(".").findFiles("*"           )) f.path.filename ].indexOf("src")   == -1
    * >>> [ for (f in Dir.of(".").findFiles("*" + "/hx/f*")) f.path.filename ].indexOf("files") == -1
    * >>> [ for (f in Dir.of(".").findFiles("**" + "/fi*" )) f.path.filename ].indexOf("files") == -1
    *
    * >>> [ for (f in Dir.of(".").findFiles("*"           )) f.path.filename ].indexOf("README.md") >  -1
    * >>> [ for (f in Dir.of(".").findFiles("**" + "/*.hx")) f.path.filename ].indexOf("Dir.hx")    >  -1
    * >>> [ for (f in Dir.of(".").findFiles("*"  + "/*.hx")) f.path.filename ].indexOf("Dir.hx")    == -1
    *
    * >>> Dir.of(""  ).findFiles("*").length == 0
    * </code></pre>
    */
   public function findFiles(globPattern:String):Array<File> {
      final files = new Array<File>();
      find(globPattern, file -> files.push(file), null);
      return files;
   }


   /**
    * <pre><code>
    * >>> Dir.of(".").list().length > 1
    *
    * >>> [ for (p in Dir.of(".").list()) p.filename ].indexOf("src"      ) > -1
    * >>> [ for (p in Dir.of(".").list()) p.filename ].indexOf("README.md") > -1
    *
    * >>> Dir.of("nonexistent").list() == []
    * >>> Dir.of("README.md").list()   throws '[path] "README.md" exists but is not a directory!'
    * <code></pre>
    */
   public function list():Array<Path> {
      if (!path.exists())
         return [];

      assertValidPath(false /*to prevent race conditions*/);

      var entries:Array<String>;

      #if (sys || macro || nodejs || phantomjs)
         try {
            #if (sys || macro || nodejs)
               entries = FileSystem.readDirectory(path.toString());
            #elseif phantomjs
               entries = [ for (entry in js.phantomjs.FileSystem.list(path.toString())) if (entry != "." && entry != "..") entry ];
            #end
         } catch (ex:Any) {
            // in case of race condition when directory is deleted during execution of this method
            if (!path.exists())
               return [];
            throw hx.strings.internal.Exception.capture(ex);
         }
      #else
         throw "Operation not supported on current target.";
      #end

      haxe.ds.ArraySort.sort(entries, Strings.compare);
      return [ for (entry in entries) @:privateAccess path.newPathForChild(entry) ];
   }


   /**
    * <pre><code>
    * >>> Dir.of(".").listDirs().length > 1
    *
    * >>> [ for (f in Dir.of(".").listDirs()) f.path.filename ].indexOf("src"      ) >  -1
    * >>> [ for (f in Dir.of(".").listDirs()) f.path.filename ].indexOf("README.md") ==  -1
    *
    * >>> Dir.of("nonexistent").listDirs() == []
    * >>> Dir.of("README.md").listDirs()   throws '[path] "README.md" exists but is not a directory!'
    * <code></pre>
    */
   public function listDirs():Array<Dir>
      return [ for (entry in list()) if (entry.isDirectory()) entry.toDir() ];


   /**
    * <pre><code>
    * >>> Dir.of(".").listFiles().length > 1
    *
    * >>> [ for (f in Dir.of(".").listFiles()) f.path.filename ].indexOf("src"      ) == -1
    * >>> [ for (f in Dir.of(".").listFiles()) f.path.filename ].indexOf("README.md") >  -1
    *
    * >>> Dir.of("nonexistent").listFiles() == []
    * >>> Dir.of("README.md").listFiles()   throws '[path] "README.md" exists but is not a directory!'
    * <code></pre>
    */
   public function listFiles():Array<File>
      return [ for (entry in list()) if (entry.isFile()) entry.toFile() ];


   /**
    * Moves the given directory and adjusts the path attribute accordingly.
    *
    * <pre><code>
    * >>> Dir.of("target/foo").create()             throws nothing
    * >>> Dir.of("target/foo").moveTo("target/bar") throws nothing
    * >>> Dir.of("target/bar").moveTo("target/bar") throws nothing
    * >>> Dir.of("target/foo").path.exists()        == false
    * >>> Dir.of("target/bar").path.exists()        == true
    * >>> Dir.of("target/bar").moveTo("")           throws "[newPath] must not be null or empty!"
    * >>> Dir.of("target/bar").delete()             == true
    * >>> Dir.of("").moveTo("")                     throws "[path.filename] must not be null or empty!"
    * </code></pre>
    *
    * @return a Dir instance pointing to the new location
    */
   public function moveTo(newPath:Either2<String, Path>, ?options:Array<DirMoveOption>):Dir {
      assertValidPath();

      if (newPath == null)
         throw "[newPath] must not be null or empty!";

      var trimWhiteSpaces = true;
      var overwrite = false;

      if (options != null) for (o in options) {
         switch(o) {
            case OVERWRITE: overwrite = true;
            case NO_WHITESPACE_TRIMMING: trimWhiteSpaces = false;
         }
      }

      final targetPath:Path = switch(newPath.value) {
         case a(str): Path.of(str, trimWhiteSpaces);
         case b(obj): obj;
      }

      if (targetPath.filename == "")
         throw "[newPath] must not be null or empty!";

      final targetDir = targetPath.toDir();

      if (targetPath.exists()) {

         if (path.getAbsolutePath() == targetPath.getAbsolutePath())
            return this;

         if (!overwrite)
            throw '[newPath] "$targetPath" already exists!';

         if (targetPath.isFile())
            targetPath.toFile().delete();
         else if (targetPath.isDirectory())
            targetDir.delete();
         else
             throw '[newPath] "$targetPath" points to an unknown file system entry!';
      }

      #if (sys || macro || nodejs)
         FileSystem.rename(path.toString(), targetPath.toString());
      #elseif phantomjs
         js.phantomjs.FileSystem.copyTree(path.toString(), targetPath.toString());
         js.phantomjs.FileSystem.removeTree(path.toString());
      #else
         throw "Operation not supported on current target.";
      #end

      return targetDir;
   }


   /**
    * Renames the given directory within it's current parent directory.
    *
    * <pre><code>
    * >>> Dir.of("target/foo").create()        throws nothing
    * >>> Dir.of("target/foo").renameTo("bar") throws nothing
    * >>> Dir.of("target/bar").path.exists()   == true
    * >>> Dir.of("target/foo").path.exists()   == false
    * >>> Dir.of("target/bar").delete()        == true
    *
    * >>> Dir.of("target/foo").renameTo("target/bar") throws '[newDirName] "target/bar" must not contain directory separators!'
    * >>> Dir.of("target/foo").renameTo("")           throws "[newDirName] must not be null or empty!"
    * >>> Dir.of(""          ).renameTo("")           throws "[newDirName] must not be null or empty!"
    * </code></pre>
    *
    * @param newDirName the new directory name (NOT the full path!)
    *
    * @return a Dir instance pointing to the new location
    */
   public function renameTo(newDirName:String, ?options:Array<DirRenameOption>):Dir {
      if (newDirName.isEmpty())
         throw "[newDirName] must not be null or empty!";

      if (newDirName.containsAny([Path.UnixPath.DIR_SEP, Path.WindowsPath.DIR_SEP]))
         throw '[newDirName] "$newDirName" must not contain directory separators!';

      var opts:Null<Array<DirMoveOption>> = null;

      if (options != null) for (o in options) {
         switch(o) {
             case OVERWRITE: opts = [OVERWRITE];
         }
      }

      if (path.parent == null)
         return moveTo(newDirName, opts);

      @:nullSafety(Off)
      return moveTo(path.parent.join(newDirName), opts);
   }


   /**
    * Changes into the directory, i.e. sets this directory as the current working directory
    */
   public function setCWD():Void {
      assertValidPath();

      #if sys
         Sys.setCwd(path.toString());
      #elseif phantomjs
         js.phantomjs.FileSystem.changeWorkingDirectory(path.toString());
      #else
         throw "Operation not supported on current target.";
      #end
   }


   /**
    * <pre><code>
    * >>> Dir.of("test"       ).size() > 100
    * >>> Dir.of("nonexistent").size() throws '[path] "nonexistent" doesn\'t exists!'
    * </code></pre>
    *
    * @return size in bytes
    */
   public function size():Int {
      if (!path.exists())
         throw '[path] "$path" doesn\'t exists!';

      var size:Int = 0;
      walk((file) -> size += file.size());
      return size;
   }


   /**
    * <pre><code>
    * >>> Dir.of("." ).walk(file -> {}, dir -> true) throws nothing
    * >>> Dir.of("." ).walk(file -> {})              throws nothing
    * >>> Dir.of("." ).walk(null)                    throws nothing
    * </code></pre>
    *
    * @param onFile callback function that is invoked on each found file
    * @param onDir callback function that is invoked on each found directory, if returns false, traversing stops
    */
   public function walk(onFile:Null<File -> Void>, ?onDir:Dir -> Bool):Void {
      var nodes:Array<Path> = list();
      while (nodes.length > 0) {
         @:nullSafety(Off)
         final node:Path = nodes.shift();
         if (node.isDirectory()) {
            var dir = node.toDir();
            if (onDir == null || onDir(dir)) {
               nodes = nodes.concat(dir.list());
            }
         } else if (onFile != null) {
            onFile(node.toFile());
         }
      }
   }

   #end // filesystem_support

   inline
   public function toString():String
      return path.toStringWithTrailingSeparator();
}


enum DirRenameOption {
   /**
    * if a directory already existing at `newPath` it will be deleted automatically
    */
   OVERWRITE;
}


enum DirCopyOption {
   /**
    * If MERGE is not specified, delete the target directory prio copying if it exists already.
    * If MERGE is specified, overwrite existing files in the target directory otherwise skip the respective source files.
    */
   OVERWRITE;

   MERGE;

   /**
    * If `newPath` is a string do not automatically remove leading/trailing whitespaces of path elements
    */
   NO_WHITESPACE_TRIMMING;

   LISTENER(onFile:(File, File) -> Void, ?onDir:(Dir, Dir) -> Void);
}


enum DirMoveOption {
   /**
    * if a directory already existing at `newPath` it will be deleted automatically
    */
   OVERWRITE;

   /**
    * If `newPath` is a string do not automatically remove leading/trailing whitespaces of path elements
    */
   NO_WHITESPACE_TRIMMING;
}
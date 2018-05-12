module UnQLite
  class DB
    getter :db_ptr, :vm_ptr, :ret_ptr, :err_ptr

    def initialize
      @err_address = 0_u32
      @err_ptr = pointerof(@err_address).as(Pointer(UInt64))

      @db_address = uninitialized Void
      @db_ptr = pointerof(@db_address).as(Pointer(LibUnQLite::UnQLiteP))

      @vm_address = uninitialized Void
      @vm_ptr = pointerof(@vm_address).as(Pointer(LibUnQLite::UnQLiteVm))
      
      @ret_address = 0_u32
      @ret_ptr = pointerof(@ret_address).as(Pointer(UInt64))
    end

    def open(path : String) : Void
      check_path = ->(x : String -> Pointer(LibUnQLite::StringP)) { if x.empty?
        f = ":mem:"
        pointerof(f).as(Pointer(LibUnQLite::StringP))
      else
        pointerof(x).as(Pointer(LibUnQLite::StringP))
      end }

      rc = LibUnQLite.unqlite_open(@db_ptr, check_path.call(path), FileOpenFlags::UNQLITE_OPEN_CREATE)
      if rc != StdUnQLiteReturn::UNQLITE_OK
        fatal(0, "Out of memory")
      end
      @opened = true
    end

    def opened? : Bool
      @opened || false
    end

    def close : Void
      if closed?
        free
        @opened = false
      end
    end

    def closed? : Bool
      !opened?
    end

    def fatal(pDb : LibUnQLite::UnQLiteP, zMsg : String) : NoReturn
      if pDb != 0
        iLen = 0_u32
        pLen = pointerof(iLen).as(Pointer(UInt64))

        LibLevelDB.unqlite_config(@db_ptr, DbHandlerConfig::UNQLITE_CONFIG_ERR_LOG, @err_ptr, pLen)
        if pLen > 0
          check_error!
        end
      else
        if !zMsg.empty?
          puts zMsg
        end
      end

      LibLevelDB.unqlite_lib_shutdown
      exit(0)
    end

    def compile(script : String) : Void
      rc = LibLevelDB.unqlite_compile(@db_ptr, script, script.bytesize, pointerof(@vm_ptr))
      if rc != StdUnQLiteReturn::UNQLITE_OK
        iLen = 0_u32
        pLen = pointerof(iLen).as(Pointer(UInt64))

        LibLevelDB.unqlite_config(@db_ptr, DbHandlerConfig::UNQLITE_CONFIG_ERR_LOG, @err_ptr, pLen)
        if pLen > 0
          check_error!
        end

        fatal(0, "Jx9 compile error")
      end

      rc = LibLevelDB.unqlite_vm_config(@vm_ptr, Jx9VmConfigCmd::UNQLITE_VM_CONFIG_OUTPUT, 0)
      if rc != StdUnQLiteReturn::UNQLITE_OK
        fatal(@db_ptr, 0)
      end
    end

    def exec : Void
      rc = LibLevelDB.unqlite_vm_exec(@vm_ptr)
      if rc != StdUnQLiteReturn::UNQLITE_OK
        fatal(@db_ptr, 0)
      end
    end

    def free
      LibLevelDB.unqlite_free(@err_ptr)
      LibLevelDB.unqlite_vm_release(@vm_ptr)
      LibLevelDB.unqlite_close(@db_ptr)
    end

    @[AlwaysInline]
    private def ensure_opened!
      raise Error.new("UnQLite DB #{@path} is closed.") if closed?
    end

    @[AlwaysInline]
    private def check_error!
      if @err_address != 0
        ptr = Pointer(UInt8).new(@err_address)
        message = String.new(ptr)
        LibLevelDB.unqlite_free(ptr)
        raise(Error.new(message))
      end
    end
  end
end

--- Compiles and installs PostgreSQL from source
--- @param ctx table Context provided by vfox
--- @field ctx.sdkInfo table SDK information with version and path
function PLUGIN:PostInstall(ctx)
    local sdkInfo = ctx.sdkInfo["postgres"]
    local version = sdkInfo.version
    local sdkPath = sdkInfo.path

    -- mise extracts tarball and strips top-level directory, so sdkPath IS the source directory

    -- Build configure options
    local configureOptions = "--prefix='" .. sdkPath .. "'"

    -- Add common options
    configureOptions = configureOptions .. " --with-openssl --with-zlib"

    -- Try to add UUID support (e2fs on Linux, BSD on macOS)
    local os_type = RUNTIME.osType
    if os_type == "darwin" then
        -- macOS: use BSD UUID
        configureOptions = configureOptions .. " --with-uuid=bsd"

        -- Add Homebrew paths for OpenSSL
        local homebrew_prefix = os.getenv("HOMEBREW_PREFIX") or "/opt/homebrew"
        local openssl_path = homebrew_prefix .. "/opt/openssl"

        -- Check if OpenSSL exists in Homebrew
        local f = io.open(openssl_path .. "/lib", "r")
        if f ~= nil then
            f:close()
            configureOptions = configureOptions .. " --with-libraries='" .. openssl_path .. "/lib'"
            configureOptions = configureOptions .. " --with-includes='" .. openssl_path .. "/include'"
        end
    else
        -- Linux: use e2fs UUID
        configureOptions = configureOptions .. " --with-uuid=e2fs"
    end

    -- Allow user to override or extend configure options
    local extraOptions = os.getenv("POSTGRES_EXTRA_CONFIGURE_OPTIONS")
    if extraOptions ~= nil and extraOptions ~= "" then
        configureOptions = configureOptions .. " " .. extraOptions
    end

    local userOptions = os.getenv("POSTGRES_CONFIGURE_OPTIONS")
    if userOptions ~= nil and userOptions ~= "" then
        -- User provided full options, use those instead (but keep prefix)
        configureOptions = "--prefix='" .. sdkPath .. "' " .. userOptions
    end

    -- Run configure
    print("Configuring PostgreSQL with: " .. configureOptions)
    local configureCmd = string.format("cd '%s' && ./configure %s", sdkPath, configureOptions)
    local status = os.execute(configureCmd)
    if status ~= 0 and status ~= true then
        error("Failed to configure PostgreSQL")
    end

    -- Build PostgreSQL
    print("Building PostgreSQL (this may take several minutes)...")
    local makeCmd = string.format("cd '%s' && make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)", sdkPath)
    status = os.execute(makeCmd)
    if status ~= 0 and status ~= true then
        error("Failed to build PostgreSQL")
    end

    -- Install PostgreSQL
    print("Installing PostgreSQL...")
    local installCmd = string.format("cd '%s' && make install", sdkPath)
    status = os.execute(installCmd)
    if status ~= 0 and status ~= true then
        error("Failed to install PostgreSQL")
    end

    -- Build and install contrib modules
    print("Building contrib modules...")
    local contribCmd = string.format("cd '%s/contrib' && make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2) && make install", sdkPath)
    status = os.execute(contribCmd)
    if status ~= 0 and status ~= true then
        -- Contrib failure is not fatal
        print("Warning: Failed to build some contrib modules")
    end

    -- Create data directory
    local dataDir = sdkPath .. "/data"
    os.execute(string.format("mkdir -p '%s'", dataDir))

    -- Run initdb unless skipped
    local skipInitdb = os.getenv("POSTGRES_SKIP_INITDB")
    if skipInitdb ~= "1" and skipInitdb ~= "true" then
        print("Initializing database cluster...")
        local initdbCmd = string.format("'%s/bin/initdb' -D '%s' -U postgres", sdkPath, dataDir)
        status = os.execute(initdbCmd)
        if status ~= 0 and status ~= true then
            print("Warning: initdb failed. You may need to run it manually.")
        end
    else
        print("Skipping initdb (POSTGRES_SKIP_INITDB is set)")
    end

    -- Clean up source files to save space
    print("Cleaning up source files...")
    local cleanCmd = string.format(
        "cd '%s' && rm -rf src doc contrib config Makefile GNUmakefile configure* aclocal* 2>/dev/null",
        sdkPath
    )
    os.execute(cleanCmd)

    print("PostgreSQL installation complete!")
end

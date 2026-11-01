case "$-" in
    *i*)
        if [ -t 1 ]; then
            /usr/sbin/picoos-motd
        fi
        ;;
esac

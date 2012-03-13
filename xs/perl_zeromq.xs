#include "perl_zeromq.h"
#include "xshelper.h"

#if (PERLZMQ_TRACE > 0)
#define PerlZMQ_trace(...) \
    { \
        PerlIO_printf(PerlIO_stderr(), "[perlzmq (%d)] ", PerlProc_getpid() ); \
        PerlIO_printf(PerlIO_stderr(), __VA_ARGS__); \
        PerlIO_printf(PerlIO_stderr(), "\n"); \
    }
#else
#define PerlZMQ_trace(...)
#endif

STATIC_INLINE void
PerlZMQ_set_bang(pTHX_ int err) {
    SV *errsv = get_sv("!", GV_ADD);
    PerlZMQ_trace(" + Set ERRSV ($!) to %d", err);
    sv_setiv(errsv, err);
}

STATIC_INLINE int
PerlZMQ_Raw_Message_mg_dup(pTHX_ MAGIC* const mg, CLONE_PARAMS* const param) {
    PerlZMQ_Raw_Message *const src = (PerlZMQ_Raw_Message *) mg->mg_ptr;
    PerlZMQ_Raw_Message *dest;

    PerlZMQ_trace("Message -> dup");
    PERL_UNUSED_VAR( param );
 
    Newxz( dest, 1, PerlZMQ_Raw_Message );
    zmq_msg_init( dest );
    zmq_msg_copy ( dest, src );
    mg->mg_ptr = (char *) dest;
    return 0;
}

STATIC_INLINE int
PerlZMQ_Raw_Message_mg_free( pTHX_ SV * const sv, MAGIC *const mg ) {
    PerlZMQ_Raw_Message* const msg = (PerlZMQ_Raw_Message *) mg->mg_ptr;

    PERL_UNUSED_VAR(sv);
    PerlZMQ_trace( "START mg_free (Message)" );
    if ( msg != NULL ) {
        PerlZMQ_trace( " + zmq message %p", msg );
        zmq_msg_close( msg );
        Safefree( msg );
    }
    PerlZMQ_trace( "END mg_free (Message)" );
    return 1;
}

STATIC_INLINE MAGIC*
PerlZMQ_Raw_Message_mg_find(pTHX_ SV* const sv, const MGVTBL* const vtbl){
    MAGIC* mg;

    assert(sv   != NULL);
    assert(vtbl != NULL);

    for(mg = SvMAGIC(sv); mg; mg = mg->mg_moremagic){
        if(mg->mg_virtual == vtbl){
            assert(mg->mg_type == PERL_MAGIC_ext);
            return mg;
        }
    }

    PerlZMQ_trace( "mg_find (Message)" );
    PerlZMQ_trace( " + SV %p", sv )
    croak("ZMQ::Raw::Message: Invalid ZMQ::Raw::Message object was passed to mg_find");
    return NULL; /* not reached */
}

STATIC_INLINE int
PerlZMQ_Raw_Context_mg_free( pTHX_ SV * const sv, MAGIC *const mg ) {
    PerlZMQ_Raw_Context* const ctxt = (PerlZMQ_Raw_Context *) mg->mg_ptr;
    PERL_UNUSED_VAR(sv);

    PerlZMQ_trace("START mg_free (Context)");
    if (ctxt != NULL) {
#ifdef USE_ITHREADS
        PerlZMQ_trace( " + thread enabled. thread %p", aTHX );
        PerlZMQ_trace( " + context wrapper %p with zmq context %p", ctxt, ctxt->ctxt );
        if ( ctxt->interp == aTHX ) { /* is where I came from */
            PerlZMQ_trace( " + detected mg_free from creating thread %p, cleaning up", aTHX );
            zmq_term( ctxt->ctxt );
            mg->mg_ptr = NULL;
            Safefree(ctxt); /* free the wrapper */
        }
#else
        PerlZMQ_trace(" + zmq context %p", ctxt);
        zmq_term( ctxt );
        mg->mg_ptr = NULL;
#endif
    }
    PerlZMQ_trace("END mg_free (Context)");
    return 1;
}

STATIC_INLINE MAGIC*
PerlZMQ_Raw_Context_mg_find(pTHX_ SV* const sv, const MGVTBL* const vtbl){
    MAGIC* mg;

    assert(sv   != NULL);
    assert(vtbl != NULL);

    for(mg = SvMAGIC(sv); mg; mg = mg->mg_moremagic){
        if(mg->mg_virtual == vtbl){
            assert(mg->mg_type == PERL_MAGIC_ext);
            return mg;
        }
    }

    croak("ZMQ::Raw::Context: Invalid ZMQ::Raw::Context object was passed to mg_find");
    return NULL; /* not reached */
}

STATIC_INLINE int
PerlZMQ_Raw_Context_mg_dup(pTHX_ MAGIC* const mg, CLONE_PARAMS* const param){
    PERL_UNUSED_VAR(mg);
    PERL_UNUSED_VAR(param);
    return 0;
}

STATIC_INLINE int
PerlZMQ_Raw_Socket_invalidate( PerlZMQ_Raw_Socket *sock )
{
    SV *ctxt_sv = sock->assoc_ctxt;
    int rv;

    PerlZMQ_trace("START socket_invalidate");
    PerlZMQ_trace(" + zmq socket %p", sock->socket);
    rv = zmq_close( sock->socket );

    if ( SvOK(ctxt_sv) ) {
        PerlZMQ_trace(" + associated context: %p", ctxt_sv);
        SvREFCNT_dec(ctxt_sv);
        sock->assoc_ctxt = NULL;
    }

    Safefree(sock);

    PerlZMQ_trace("END socket_invalidate");
    return rv;
}

STATIC_INLINE int
PerlZMQ_Raw_Socket_mg_free(pTHX_ SV* const sv, MAGIC* const mg)
{
    PerlZMQ_Raw_Socket* const sock = (PerlZMQ_Raw_Socket *) mg->mg_ptr;
    PERL_UNUSED_VAR(sv);
    PerlZMQ_trace("START mg_free (Socket)");
    if (sock) {
        PerlZMQ_Raw_Socket_invalidate( sock );
        mg->mg_ptr = NULL;
    }
    PerlZMQ_trace("END mg_free (Socket)");
    return 1;
}

STATIC_INLINE int
PerlZMQ_Raw_Socket_mg_dup(pTHX_ MAGIC* const mg, CLONE_PARAMS* const param){
    PerlZMQ_trace("START mg_dup (Socket)");
#ifdef USE_ITHREADS /* single threaded perl has no "xxx_dup()" APIs */
    mg->mg_ptr = NULL;
    PERL_UNUSED_VAR(param);
#else
    PERL_UNUSED_VAR(mg);
    PERL_UNUSED_VAR(param);
#endif
    PerlZMQ_trace("END mg_dup (Socket)");
    return 0;
}

STATIC_INLINE MAGIC*
PerlZMQ_Raw_Socket_mg_find(pTHX_ SV* const sv, const MGVTBL* const vtbl){
    MAGIC* mg;

    assert(sv   != NULL);
    assert(vtbl != NULL);

    for(mg = SvMAGIC(sv); mg; mg = mg->mg_moremagic){
        if(mg->mg_virtual == vtbl){
            assert(mg->mg_type == PERL_MAGIC_ext);
            return mg;
        }
    }

    croak("ZMQ::Socket: Invalid ZMQ::Socket object was passed to mg_find");
    return NULL; /* not reached */
}

STATIC_INLINE void 
PerlZMQ_free_string(void *data, void *hint) {
    PERL_SET_CONTEXT(hint);
    Safefree( (char *) data );
}

#include "mg-xs.inc"

MODULE = ZMQ    PACKAGE = ZMQ   PREFIX = PerlZMQ_

PROTOTYPES: DISABLED

BOOT:
    {
        PerlZMQ_trace( "Booting Perl ZMQ" );
    }

void
PerlZMQ_version()
    PREINIT:
        int major, minor, patch;
        I32 gimme;
    PPCODE:
        gimme = GIMME_V;
        if (gimme == G_VOID) {
            /* WTF? you don't want a return value?! */
            XSRETURN(0);
        }

        zmq_version(&major, &minor, &patch);
        if (gimme == G_SCALAR) {
            XPUSHs( sv_2mortal( newSVpvf( "%d.%d.%d", major, minor, patch ) ) );
            XSRETURN(1);
        } else {
            mXPUSHi( major );
            mXPUSHi( minor );
            mXPUSHi( patch );
            XSRETURN(3);
        }

MODULE = ZMQ    PACKAGE = ZMQ::Constants 

INCLUDE: const-xs.inc

MODULE = ZMQ    PACKAGE = ZMQ::Raw  PREFIX = PerlZMQ_Raw_

PROTOTYPES: DISABLED

PerlZMQ_Raw_Context *
PerlZMQ_Raw_zmq_init( nthreads = 5 )
        int nthreads;
    PREINIT:
        SV *class_sv = sv_2mortal(newSVpvn( "ZMQ::Raw::Context", 20 ));
    CODE:
        PerlZMQ_trace( "START zmq_init" );
#ifdef USE_ITHREADS
        PerlZMQ_trace( " + threads enabled, aTHX %p", aTHX );
        Newxz( RETVAL, 1, PerlZMQ_Raw_Context );
        RETVAL->interp = aTHX;
        RETVAL->ctxt   = zmq_init( nthreads );
        PerlZMQ_trace( " + created context wrapper %p", RETVAL );
        PerlZMQ_trace( " + zmq context %p", RETVAL->ctxt );
#else
        PerlZMQ_trace( " + non-threaded context");
        RETVAL = zmq_init( nthreads );
#endif
        PerlZMQ_trace( "END zmq_init");
    OUTPUT:
        RETVAL

int
PerlZMQ_Raw_zmq_term( context )
        PerlZMQ_Raw_Context *context;
    CODE:
#ifdef USE_ITHREADS
        RETVAL = zmq_term( context->ctxt );
#else
        RETVAL = zmq_term( context );
#endif
        if (RETVAL == 0) {
            /* Cancel the SV's mg attr so to not call zmq_term automatically */
            MAGIC *mg =
                PerlZMQ_Raw_Context_mg_find( aTHX_ SvRV(ST(0)), &PerlZMQ_Raw_Context_vtbl );
            mg->mg_ptr = NULL;
        }

        /* mark the original SV's _closed flag as true */
        {
            SV *svr = SvRV(ST(0));
            if (hv_stores( (HV *) svr, "_closed", &PL_sv_yes ) == NULL) {
                croak("PANIC: Failed to store closed flag on blessed reference");
            }
        }
    OUTPUT:
        RETVAL

PerlZMQ_Raw_Message *
PerlZMQ_Raw_zmq_msg_init()
    PREINIT:
        SV *class_sv = sv_2mortal(newSVpvn( "ZMQ::Raw::Message", 20 ));
        int rc;
    CODE:
        Newxz( RETVAL, 1, PerlZMQ_Raw_Message );
        rc = zmq_msg_init( RETVAL );
        if ( rc != 0 ) {
            SET_BANG;
            zmq_msg_close( RETVAL );
            RETVAL = NULL;
        }
    OUTPUT:
        RETVAL

PerlZMQ_Raw_Message *
PerlZMQ_Raw_zmq_msg_init_size( size )
        IV size;
    PREINIT:
        SV *class_sv = sv_2mortal(newSVpvn( "ZMQ::Raw::Message", 20 ));
        int rc;
    CODE: 
        Newxz( RETVAL, 1, PerlZMQ_Raw_Message );
        rc = zmq_msg_init_size(RETVAL, size);
        if ( rc != 0 ) {
            SET_BANG;
            zmq_msg_close( RETVAL );
            RETVAL = NULL;
        }
    OUTPUT:
        RETVAL

PerlZMQ_Raw_Message *
PerlZMQ_Raw_zmq_msg_init_data( data, size = -1)
        SV *data;
        IV size;
    PREINIT:
        SV *class_sv = sv_2mortal(newSVpvn( "ZMQ::Raw::Message", 20 ));
        STRLEN x_data_len;
        char *sv_data = SvPV(data, x_data_len);
        char *x_data;
        int rc;
    CODE: 
        PerlZMQ_trace("START zmq_msg_init_data");
        if (size >= 0) {
            x_data_len = size;
        }
        Newxz( RETVAL, 1, PerlZMQ_Raw_Message );
        Newxz( x_data, x_data_len, char );
        Copy( sv_data, x_data, x_data_len, char );
        rc = zmq_msg_init_data(RETVAL, x_data, x_data_len, PerlZMQ_free_string, Perl_get_context());
        if ( rc != 0 ) {
            SET_BANG;
            zmq_msg_close( RETVAL );
            RETVAL = NULL;
        }
        else {
            PerlZMQ_trace(" + zmq_msg_init_data created message %p", RETVAL);
        }
        PerlZMQ_trace("END zmq_msg_init_data");
    OUTPUT:
        RETVAL

SV *
PerlZMQ_Raw_zmq_msg_data(message)
        PerlZMQ_Raw_Message *message;
    CODE:
        PerlZMQ_trace( "START zmq_msg_data" );
        PerlZMQ_trace( " + message content '%s'", (char *) zmq_msg_data(message) );
        PerlZMQ_trace( " + message size '%d'", (int) zmq_msg_size(message) );
        RETVAL = newSV(0);
        sv_setpvn( RETVAL, (char *) zmq_msg_data(message), (STRLEN) zmq_msg_size(message) );
        PerlZMQ_trace( "END zmq_msg_data" );
    OUTPUT:
        RETVAL

size_t
PerlZMQ_Raw_zmq_msg_size(message)
        PerlZMQ_Raw_Message *message;
    CODE:
        RETVAL = zmq_msg_size(message);
    OUTPUT:
        RETVAL

int
PerlZMQ_Raw_zmq_msg_close(message)
        PerlZMQ_Raw_Message *message;
    CODE:
        PerlZMQ_trace("START zmq_msg_close");
        RETVAL = zmq_msg_close(message);
        Safefree(message);
        {
            MAGIC *mg =
                 PerlZMQ_Raw_Message_mg_find( aTHX_ SvRV(ST(0)), &PerlZMQ_Raw_Message_vtbl );
             mg->mg_ptr = NULL;
        }
        /* mark the original SV's _closed flag as true */
        {
            SV *svr = SvRV(ST(0));
            if (hv_stores( (HV *) svr, "_closed", &PL_sv_yes ) == NULL) {
                croak("PANIC: Failed to store closed flag on blessed reference");
            }
        }
        PerlZMQ_trace("END zmq_msg_close");
    OUTPUT:
        RETVAL

int
PerlZMQ_Raw_zmq_msg_move(dest, src)
        PerlZMQ_Raw_Message *dest;
        PerlZMQ_Raw_Message *src;
    CODE:
        RETVAL = zmq_msg_move( dest, src );
    OUTPUT:
        RETVAL

int
PerlZMQ_Raw_zmq_msg_copy (dest, src);
        PerlZMQ_Raw_Message *dest;
        PerlZMQ_Raw_Message *src;
    CODE:
        RETVAL = zmq_msg_copy( dest, src );
    OUTPUT:
        RETVAL

PerlZMQ_Raw_Socket *
PerlZMQ_Raw_zmq_socket (ctxt, type)
        PerlZMQ_Raw_Context *ctxt;
        IV type;
    PREINIT:
        SV *class_sv = sv_2mortal(newSVpvn( "ZMQ::Raw::Socket", 19 ));
    CODE:
        PerlZMQ_trace( "START zmq_socket" );
        Newxz( RETVAL, 1, PerlZMQ_Raw_Socket );
        RETVAL->assoc_ctxt = NULL;
        RETVAL->socket = NULL;
#ifdef USE_ITHREADS
        PerlZMQ_trace( " + context wrapper %p, zmq context %p", ctxt, ctxt->ctxt );
        RETVAL->socket = zmq_socket( ctxt->ctxt, type );
#else
        PerlZMQ_trace( " + zmq context %p", ctxt );
        RETVAL->socket = zmq_socket( ctxt, type );
#endif
        RETVAL->assoc_ctxt = ST(0);
        SvREFCNT_inc(RETVAL->assoc_ctxt);
        PerlZMQ_trace( " + created socket %p", RETVAL );
        PerlZMQ_trace( "END zmq_socket" );
    OUTPUT:
        RETVAL

int
PerlZMQ_Raw_zmq_close(socket)
        PerlZMQ_Raw_Socket *socket;
    CODE:
        RETVAL = PerlZMQ_Raw_Socket_invalidate( socket );
        /* Cancel the SV's mg attr so to not call socket_invalidate again
           during Socket_mg_free
        */
        {
            MAGIC *mg =
                 PerlZMQ_Raw_Socket_mg_find( aTHX_ SvRV(ST(0)), &PerlZMQ_Raw_Socket_vtbl );
             mg->mg_ptr = NULL;
        }

        /* mark the original SV's _closed flag as true */
        {
            SV *svr = SvRV(ST(0));
            if (hv_stores( (HV *) svr, "_closed", &PL_sv_yes ) == NULL) {
                croak("PANIC: Failed to store closed flag on blessed reference");
            }
        }
    OUTPUT:
        RETVAL

int
PerlZMQ_Raw_zmq_connect(socket, addr)
        PerlZMQ_Raw_Socket *socket;
        char *addr;
    CODE:
        PerlZMQ_trace( "START zmq_connect" );
        PerlZMQ_trace( " + socket %p", socket );
        RETVAL = zmq_connect( socket->socket, addr );
        PerlZMQ_trace(" + zmq_connect returned with rv '%d'", RETVAL);
        if (RETVAL != 0) {
            PerlZMQ_set_bang( aTHX_ zmq_errno() );
        }
        PerlZMQ_trace( "END zmq_connect" );
    OUTPUT:
        RETVAL

int
PerlZMQ_Raw_zmq_bind(socket, addr)
        PerlZMQ_Raw_Socket *socket;
        char *addr;
    CODE:
        PerlZMQ_trace( "START zmq_bind" );
        PerlZMQ_trace( " + socket %p", socket );
        RETVAL = zmq_bind( socket->socket, addr );
        PerlZMQ_trace(" + zmq_bind returned with rv '%d'", RETVAL);
        if (RETVAL != 0) {
            PerlZMQ_set_bang( aTHX_ zmq_errno() );
        }
        PerlZMQ_trace( "END zmq_bind" );
    OUTPUT:
        RETVAL

PerlZMQ_Raw_Message *
PerlZMQ_Raw_zmq_recvmsg(socket, flags = 0)
        PerlZMQ_Raw_Socket *socket;
        int flags;
    PREINIT:
        SV *class_sv = sv_2mortal(newSVpvn( "ZMQ::Raw::Message", 20 ));
        int rv;
        zmq_msg_t msg;
    CODE:
        PerlZMQ_trace( "START zmq_recvmsg" );
        RETVAL = NULL;
        rv = zmq_msg_init(&msg);
        if (rv != 0) {
            PerlZMQ_trace("zmq_msg_init failed (%d)", rv);
            PerlZMQ_set_bang( aTHX_ zmq_errno() );
            XSRETURN_UNDEF;
        }
        rv = zmq_recvmsg(socket->socket, &msg, flags);
        PerlZMQ_trace(" + zmq_recvmsg with flags %d", flags);
        PerlZMQ_trace(" + zmq_recvmsg returned with rv '%d'", rv);
        if (rv < 0) {
            SET_BANG;
            zmq_msg_close(&msg);
            PerlZMQ_trace(" + zmq_recvmsg got bad status, closing temporary message");
        } else {
            PerlZMQ_trace(" + message data (%s)", (char *) zmq_msg_data(&msg) );
            PerlZMQ_trace(" + message size (%d)", (int) zmq_msg_size(&msg) );
            Newxz(RETVAL, 1, PerlZMQ_Raw_Message);
            zmq_msg_init(RETVAL);
            zmq_msg_copy( RETVAL, &msg );
            PerlZMQ_trace(" + zmq_recvmsg created message %p", RETVAL );
            zmq_msg_close(&msg);
        }
        PerlZMQ_trace( "END zmq_recvmsg" );
    OUTPUT:
        RETVAL

int
PerlZMQ_Raw_zmq_send(socket, message, size = -1, flags = 0)
        PerlZMQ_Raw_Socket *socket;
        SV *message;
        int size;
        int flags;
    PREINIT:
        char *message_buf;
        STRLEN usize;
    CODE:
        PerlZMQ_trace( "START zmq_send" );
        if (! SvOK(message))
            croak("ZMQ::Raw::zmq_send(): NULL message passed");

        message_buf = SvPV( message, usize );
        if ( size != -1 && (STRLEN)size < usize )
            usize = (STRLEN)size;

        PerlZMQ_trace( " + buffer '%s' (%zu)", message_buf, usize );
        PerlZMQ_trace( " + flags %d", flags);
        RETVAL = zmq_send( socket->socket, message_buf, usize, flags );
        PerlZMQ_trace( " + zmq_send returned with rv '%d'", RETVAL );
        if ( RETVAL == -1 ) {
            PerlZMQ_trace( " ! zmq_send error %s", zmq_strerror( zmq_errno() ) );
            PerlZMQ_set_bang( aTHX_ zmq_errno() );
        }
        PerlZMQ_trace( "END zmq_send" );
    OUTPUT:
        RETVAL

int
PerlZMQ_Raw_zmq_sendmsg(socket, message, flags = 0)
        PerlZMQ_Raw_Socket *socket;
        PerlZMQ_Raw_Message *message;
        int flags;
    CODE:
        PerlZMQ_trace( "START zmq_sendmsg" );
        if (message == NULL)
            croak("ZMQ::Raw::zmq_sendmsg() NULL message passed");

        RETVAL = zmq_sendmsg(socket->socket, message, flags);
        PerlZMQ_trace( " + zmq_sendmsg returned with rv '%d'", RETVAL );
        if ( RETVAL == -1 ) {
            PerlZMQ_trace( " ! zmq_sendmsg error %s", zmq_strerror( zmq_errno() ) );
            PerlZMQ_set_bang( aTHX_ zmq_errno() );
        }
        PerlZMQ_trace( "END zmq_sendmsg" );
    OUTPUT:
        RETVAL

#define SOCKOPT_BUFSIZ 1024
SV *
PerlZMQ_Raw_zmq_getsockopt(sock, option)
        PerlZMQ_Raw_Socket *sock;
        int option;
    PREINIT:
        char     buf[SOCKOPT_BUFSIZ];
        int      i;
        uint64_t u64;
        int64_t  i64;
        uint32_t i32;
        size_t   len;
        int      status = -1;
    CODE:
        switch(option){
            case ZMQ_BACKLOG:
            case ZMQ_FD:
            case ZMQ_LINGER:
            case ZMQ_RECOVERY_IVL:
            case ZMQ_RECONNECT_IVL:
            case ZMQ_RECONNECT_IVL_MAX:
            case ZMQ_RCVMORE:
            case ZMQ_TYPE:
                len = sizeof(i);
                status = zmq_getsockopt(sock->socket, option, &i, &len);
                if(status == 0)
                    RETVAL = newSViv(i);
                break;

            case ZMQ_RATE:
                len = sizeof(i64);
                status = zmq_getsockopt(sock->socket, option, &i64, &len);
                if(status == 0)
                    RETVAL = newSViv(i64);
                break;

            case ZMQ_RCVHWM:
            case ZMQ_SNDHWM:
            case ZMQ_AFFINITY:
            case ZMQ_SNDBUF:
            case ZMQ_RCVBUF:
                len = sizeof(u64);
                status = zmq_getsockopt(sock->socket, option, &u64, &len);
                if(status == 0)
                    RETVAL = newSVuv(u64);
                break;

            case ZMQ_EVENTS:
                len = sizeof(i32);
                status = zmq_getsockopt(sock->socket, option, &i32, &len);
                if(status == 0)
                    RETVAL = newSViv(i32);
                break;

            case ZMQ_IDENTITY:
                len = SOCKOPT_BUFSIZ;
                status = zmq_getsockopt(sock->socket, option, &buf, &len);
                if(status == 0)
                    RETVAL = newSVpvn(buf, len);
                break;

            default:
                len = SOCKOPT_BUFSIZ;
                warn("Unknown sockopt type %d, assuming string.  Send patch", option);
                status = zmq_setsockopt(sock->socket, option, buf, len);
                if(status == 0)
                    RETVAL = newSVpvn(buf, len);
                break;
        }
        if (status != 0) {
            PerlZMQ_set_bang( aTHX_ zmq_errno() );
        }
    OUTPUT:
        RETVAL

int
PerlZMQ_Raw_zmq_setsockopt(sock, option, value)
        PerlZMQ_Raw_Socket *sock;
        int option;
        SV *value;
    PREINIT:
        STRLEN len;
        const char *ptr;
        uint64_t u64;
        int64_t  i64;
        int i;
    CODE:
        switch(option){
            case ZMQ_IDENTITY:
            case ZMQ_SUBSCRIBE:
            case ZMQ_UNSUBSCRIBE:
                ptr = SvPV(value, len);
                RETVAL = zmq_setsockopt(sock->socket, option, ptr, len);
                break;

            case ZMQ_RATE:
                i64 = SvIV(value);
                RETVAL = zmq_setsockopt(sock->socket, option, &i64, sizeof(int64_t));
                break;

            case ZMQ_SNDHWM:
            case ZMQ_RCVHWM:
            case ZMQ_AFFINITY:
            case ZMQ_SNDBUF:
            case ZMQ_RCVBUF:
                u64 = SvUV(value);
                RETVAL = zmq_setsockopt(sock->socket, option, &u64, sizeof(uint64_t));
                break;

            case ZMQ_RECOVERY_IVL:
            case ZMQ_RECONNECT_IVL:
            case ZMQ_RECONNECT_IVL_MAX:
            case ZMQ_LINGER:
                i = SvIV(value);
                RETVAL = zmq_setsockopt(sock->socket, option, &i, sizeof(i));
                break;

            default:
                warn("Unknown sockopt type %d, assuming string.  Send patch", option);
                ptr = SvPV(value, len);
                RETVAL = zmq_setsockopt(sock->socket, option, ptr, len);
        }
        if (RETVAL == 0) {
            PerlZMQ_set_bang( aTHX_ zmq_errno() );
        }
    OUTPUT:
        RETVAL

int
PerlZMQ_Raw_zmq_poll( list, timeout = 0 )
        AV *list;
        long timeout;
    PREINIT:
        I32 list_len;
        zmq_pollitem_t *pollitems;
        CV **callbacks;
        int i;
    CODE:
        PerlZMQ_trace( "START zmq_poll" );

        list_len = av_len( list ) + 1;
        if (list_len <= 0) {
            XSRETURN(0);
        }

        Newxz( pollitems, list_len, zmq_pollitem_t);
        Newxz( callbacks, list_len, CV *);

        /* list should be a list of hashrefs fd, events, and callbacks */
        for (i = 0; i < list_len; i++) {
            SV **svr = av_fetch( list, i, 0 );
            HV  *elm;

            PerlZMQ_trace( " + processing element %d", i );
            if (svr == NULL || ! SvOK(*svr) || ! SvROK(*svr) || SvTYPE(SvRV(*svr)) != SVt_PVHV) {
                Safefree( pollitems );
                Safefree( callbacks );
                croak("Invalid value on index %d", i);
            }
            elm = (HV *) SvRV(*svr);

            callbacks[i] = NULL;
            pollitems[i].revents = 0;
            pollitems[i].events  = 0;
            pollitems[i].fd      = 0;
            pollitems[i].socket  = NULL;

            svr = hv_fetch( elm, "socket", 6, NULL );
            if (svr != NULL) {
                MAGIC *mg;
                if (! SvOK(*svr) || !sv_isobject( *svr) || ! sv_isa(*svr, "ZMQ::Raw::Socket")) {
                    Safefree( pollitems );
                    Safefree( callbacks );
                    croak("Invalid 'socket' given for index %d", i);
                }
                mg = PerlZMQ_Raw_Socket_mg_find( aTHX_ SvRV(*svr), &PerlZMQ_Raw_Socket_vtbl );
                pollitems[i].socket = ((PerlZMQ_Raw_Socket *) mg->mg_ptr)->socket;
                PerlZMQ_trace( " + via pollitem[%d].socket = %p", i, pollitems[i].socket );
            } else {
                svr = hv_fetch( elm, "fd", 2, NULL );
                if (svr == NULL || ! SvOK(*svr) || SvTYPE(*svr) != SVt_IV) {
                    Safefree( pollitems );
                    Safefree( callbacks );
                    croak("Invalid 'fd' given for index %d", i);
                }
                pollitems[i].fd = SvIV( *svr );
                PerlZMQ_trace( " + via pollitem[%d].fd = %d", i, pollitems[i].fd );
            }

            svr = hv_fetch( elm, "events", 6, NULL );
            if (svr == NULL || ! SvOK(*svr) || SvTYPE(*svr) != SVt_IV) {
                Safefree( pollitems );
                Safefree( callbacks );
                croak("Invalid 'events' given for index %d", i);
            }
            pollitems[i].events = SvIV( *svr );
            PerlZMQ_trace( " + going to poll events %d", pollitems[i].events );

            svr = hv_fetch( elm, "callback", 8, NULL );
            if (svr == NULL || ! SvOK(*svr) || ! SvROK(*svr) || SvTYPE(SvRV(*svr)) != SVt_PVCV) {
                Safefree( pollitems );
                Safefree( callbacks );
                croak("Invalid 'callback' given for index %d", i);
            }
            callbacks[i] = (CV *) SvRV( *svr );
        }

        /* now call zmq_poll */
        RETVAL = zmq_poll( pollitems, list_len, timeout );
        PerlZMQ_trace( " + zmq_poll returned with rv '%d'", RETVAL );

        if (RETVAL > 0) {
            for ( i = 0; i < list_len; i++ ) {
                PerlZMQ_trace( " + checking events for %d", i );
                if (! (pollitems[i].revents & pollitems[i].events) ) {
                    PerlZMQ_trace( " + no events for %d", i );
                    break;
                }

                PerlZMQ_trace( " + got events for %d", i );
                {
                    dSP;
                    ENTER;
                    SAVETMPS;
                    PUSHMARK(SP);
                    PUTBACK;

                    call_sv( (SV*)callbacks[i], G_SCALAR );
                    SPAGAIN;

                    PUTBACK;
                    FREETMPS;
                    LEAVE;
                }
            }
        }
        Safefree(pollitems);
        Safefree(callbacks);
        PerlZMQ_trace( "END zmq_poll" );
    OUTPUT:
        RETVAL



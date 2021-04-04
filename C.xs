#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#ifndef PM_GETRE
# if defined(USE_ITHREADS) && (PERL_VERSION > 8)
#  define PM_GETRE(o)     (INT2PTR(REGEXP*,SvIVX(PL_regex_pad[(o)->op_pmoffset])))
# else
#  define PM_GETRE(o)     ((o)->op_pmregexp)
# endif
#endif
#ifndef RX_EXTFLAGS
# define RX_EXTFLAGS(prog) ((prog)->extflags)
#endif

typedef struct magic  *B__MAGIC;
#if PERL_VERSION >= 11
typedef struct p5rx  *B__REGEXP;
#endif
typedef COP  *B__COP;

STATIC U32 a_hash = 0;

typedef struct {
  U32 bits;
  IV  require_tag;
} a_hint_t;

static int
my_runops(pTHX)
{
    HV* regexp_hv = get_hv( "B::C::Regexp", 0 );
    SV* key = newSViv( 0 );

    DEBUG_l(Perl_deb(aTHX_ "Entering new RUNOPS level (B::C)\n"));
    do {
#if (PERL_VERSION < 13) || ((PERL_VERSION == 13) && (PERL_SUBVERSION < 2))
	PERL_ASYNC_CHECK();
#endif

	if (PL_debug) {
	    if (PL_watchaddr && (*PL_watchaddr != PL_watchok))
		PerlIO_printf(Perl_debug_log,
			      "WARNING: %"UVxf" changed from %"UVxf" to %"UVxf"\n",
			      PTR2UV(PL_watchaddr), PTR2UV(PL_watchok),
			      PTR2UV(*PL_watchaddr));
#if defined(DEBUGGING) \
   && !(defined(_WIN32) || (defined(__CYGWIN__) && (__GNUC__ > 3)) || defined(AIX))
# if (PERL_VERSION > 7)
	    if (DEBUG_s_TEST_) debstack();
	    if (DEBUG_t_TEST_) debop(PL_op);
# else
	    DEBUG_s(debstack());
	    DEBUG_t(debop(PL_op));
# endif
#endif
	}

        if( PL_op->op_type == OP_QR ) {
            PMOP* op;
            REGEXP* rx = PM_GETRE( (PMOP*)PL_op );
            SV* rv = newSViv( 0 );

            New(0, op, 1, PMOP );
            Copy( PL_op, op, 1, PMOP );
            /* we need just the flags */
            op->op_next = NULL;
            op->op_sibling = NULL;
            op->op_first = NULL;
            op->op_last = NULL;

#if PERL_VERSION < 10
            op->op_pmreplroot = NULL;
            op->op_pmreplstart = NULL;
            op->op_pmnext = NULL;
#endif
#if defined(USE_ITHREADS) && (PERL_VERSION > 7)
            op->op_pmoffset = 0;
#else
            op->op_pmregexp = 0;
#endif

            sv_setiv( key, PTR2IV( rx ) );
            sv_setref_iv( rv, "B::PMOP", PTR2IV( op ) );

            hv_store_ent( regexp_hv, key, rv, 0 );
        }
    } while ((PL_op = CALL_FPTR(PL_op->op_ppaddr)(aTHX)));

    SvREFCNT_dec( key );

    TAINT_NOT;
    return 0;
}

MODULE = B__MAGIC	PACKAGE = B::MAGIC

#if PERL_VERSION < 7

SV*
precomp(mg)
        B::MAGIC        mg
    CODE:
        if (mg->mg_type == 'r') {
            REGEXP* rx = (REGEXP*)mg->mg_obj;
            RETVAL = Nullsv;
            if (rx)
                RETVAL = newSVpvn( rx->precomp, rx->prelen );
        }
        else {
            croak( "precomp is only meaningful on r-magic" );
        }
    OUTPUT:
        RETVAL

#endif

MODULE = B	PACKAGE = B::REGEXP	PREFIX = RX_

#if PERL_VERSION > 10

U32
RX_EXTFLAGS(rx)
	  B::REGEXP rx

#endif

MODULE = B	PACKAGE = B::COP	PREFIX = COP_

#if (PERL_VERSION >= 15) && defined(USE_ITHREADS) && defined(CopSTASH_flags)

#define COP_stashflags(o)	CopSTASH_flags(o)

U32
COP_stashflags(o)
	B::COP	o

#endif

MODULE = B__CC	PACKAGE = B::CC

PROTOTYPES: DISABLE

U32
_autovivification(cop)
	B::COP	cop
CODE:
    {
      SV *hint;
      IV h;

      RETVAL = 1;
      if (PL_check[OP_PADSV] != PL_check[0]) {
	char *package = CopSTASHPV(cop);
#ifdef cop_hints_fetch_pvn
	hint = cop_hints_fetch_pvn(cop, "autovivification", strlen("autovivification"), a_hash, 0);
#elif PERL_VERSION > 9
	hint = Perl_refcounted_he_fetch(aTHX_ cop->cop_hints_hash,
					NULL, "autovivification", strlen("autovivification"), 0, a_hash);
#else
	SV **val = hv_fetch(GvHV(PL_hintgv), "autovivification", strlen("autovivification"), 0);
	if (!val)
	  return;
	hint = *val;
#endif
	if (!(hint && SvIOK(hint)))
	  return;
	h = SvIVX(hint);
	if (h & 4)  /* A_HINT_FETCH  4 */
	  RETVAL = 0;
      }
    }
OUTPUT:
  RETVAL

MODULE = B__C	PACKAGE = B::C

PROTOTYPES: DISABLE

BOOT:
    PL_runops = my_runops;

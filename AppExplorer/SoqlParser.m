//
//  SoqlParser.m
//  ZKParser
//
//  Created by Simon Fell on 4/9/21.
//  Copyright © 2021 Simon Fell. All rights reserved.
//

#import "SoqlParser.h"
#import "ZKParserFactory.h"
#import "SoqlToken.h"

const NSString *KeyTokens = @"tokens";
const NSString *KeySoqlText = @"soql";



@interface SoqlParser()
@property (strong,nonatomic) ZKBaseParser *parser;
@end

@implementation SoqlParser

-(instancetype)init {
    self = [super init];
    self.parser = [self buildParser];
    return self;
}

-(NSArray<Token*>*)parse:(NSString *)input error:(NSError**)err {
    NSDictionary *ctx = @{KeyTokens: [Tokens new],
                          KeySoqlText:input,
    };
    ZKParsingState *state = [ZKParsingState withInput:input];
    state.userContext = ctx;
    [state parse:self.parser error:err];
    return ctx[KeyTokens];
}

-(ZKSingularParser*)literalStringValue:(ZKParserFactory*)f {
    ZKSingularParser *p = [f fromBlock:^ZKParserResult *(ZKParsingState *input, NSError *__autoreleasing *err) {
        NSInteger start = input.pos;
        if ((!input.hasMoreInput) || input.currentChar != '\'') {
            *err = [NSError errorWithDomain:@"Soql"
                                      code:1
                                  userInfo:@{
                                      NSLocalizedDescriptionKey:[NSString stringWithFormat:@"expecting ' at position %lu", input.pos+1],
                                      @"Position": @(input.pos+1)
                                  }];
            return nil;
        }
        input.pos++;
        [input markCut];
        while (true) {
            if (!input.hasMoreInput) {
                *err = [NSError errorWithDomain:@"Soql"
                                          code:1
                                      userInfo:@{
                                          NSLocalizedDescriptionKey:[NSString stringWithFormat:@"reached end of input while parsing a string literal, missing closing ' at %lu", input.pos+1],
                                          @"Position": @(input.pos+1)
                                      }];
                return nil;
            }
            unichar c = input.currentChar;
            if (c == '\\') {
                input.pos++;
                if (!input.hasMoreInput) {
                    *err = [NSError errorWithDomain:@"Soql"
                                              code:1
                                          userInfo:@{
                                              NSLocalizedDescriptionKey:[NSString stringWithFormat:@"invalid escape sequence at %lu", input.pos],
                                              @"Position": @(input.pos)
                                          }];
                }
                input.pos++;
                continue;
            }
            input.pos++;
            if (c == '\'') {
                break;
            }
        }
        // range includes the ' tokens, the value does not.
        NSRange overalRng = NSMakeRange(start,input.pos-start);
        Token *t = [Token txt:input.input loc:overalRng];
        t.type = TTLiteral;
        return [ZKParserResult result:t ctx:input.userContext loc:overalRng];
    }];
    p.debugName = @"Literal String";
    return p;
}

-(ZKBaseParser*)literalValue:(ZKParserFactory*)f {
    ZKBaseParser *literalStringValue = [self literalStringValue:f];
    ZKBaseParser *literalNullValue = [[f eq:@"null"] onMatch:^ZKParserResult *(ZKParserResult *r) {
        Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.loc];
        t.type = TTLiteral;
        t.value = [NSNull null];
        r.val = t;
        return r;
    }];
    ZKBaseParser *literalTrueValue = [[f eq:@"true"] onMatch:^ZKParserResult *(ZKParserResult *r) {
        Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.loc];
        t.type = TTLiteral;
        t.value = @TRUE;
        r.val = t;
        return r;
    }];
    ZKBaseParser *literalFalseValue = [[f eq:@"false"] onMatch:^ZKParserResult *(ZKParserResult *r) {
        Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.loc];
        t.type = TTLiteral;
        t.value = @FALSE;
        r.val = t;
        return r;
    }];
    ZKBaseParser *literalNumberValue = [[f decimalNumber] onMatch:^ZKParserResult *(ZKParserResult *r) {
        Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.loc];
        t.type = TTLiteral;
        t.value = r.val;
        r.val = t;
        return r;
    }];
    NSError *err = nil;
    NSRegularExpression *dateTime = [NSRegularExpression regularExpressionWithPattern:@"\\d\\d\\d\\d-\\d\\d-\\d\\d(?:T\\d\\d:\\d\\d:\\d\\d(?:Z|[+-]\\d\\d:\\d\\d))?"
                                                                              options:NSRegularExpressionCaseInsensitive
                                                                                error:&err];
    NSAssert(err == nil, @"failed to compile regex %@", err);
    NSISO8601DateFormatter *dfDateTime = [NSISO8601DateFormatter new];
    NSISO8601DateFormatter *dfDate = [NSISO8601DateFormatter new];
    dfDate.formatOptions = NSISO8601DateFormatWithFullDate | NSISO8601DateFormatWithDashSeparatorInDate;
    ZKBaseParser *literalDateTimeValue = [[f regex:dateTime name:@"date/time literal"] onMatch:^ZKParserResult *(ZKParserResult *r) {
        Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.loc];
        t.type = TTLiteral;
        NSString *dt = r.val;
        if (dt.length == 10) {
            t.value = [dfDate dateFromString:dt];
        } else {
            t.value = [dfDateTime dateFromString:dt];
        }
        r.val = t;
        return r;
    }];
    NSRegularExpression *token = [NSRegularExpression regularExpressionWithPattern:@"[a-z]\\S*"
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&err];
    NSAssert(err == nil, @"failed to compile regex %@", err);
    ZKBaseParser *literalToken = [[f regex:token name:@"named literal"] onMatch:^ZKParserResult *(ZKParserResult *r) {
        Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.loc];
        t.type = TTLiteral;
        t.value = r.val;
        r.val = t;
        return r;
    }];
    ZKBaseParser *literalValue = [[f oneOf:@[literalStringValue, literalNullValue, literalTrueValue, literalFalseValue, literalNumberValue, literalDateTimeValue, literalToken]] onMatch:^ZKParserResult *(ZKParserResult *r) {
            [r.userContext[KeyTokens] addToken:r.val];
            return r;
    }];
    return literalValue;
}

-(ZKBaseParser*)buildParser {
    ZKParserFactory *f = [ZKParserFactory new];
    // f.debugFile = @"/Users/simon/Github/ZKParser/soql.debug";
    f.defaultCaseSensitivity = CaseInsensitive;

    ZKBaseParser* ws = [f characters:[NSCharacterSet whitespaceAndNewlineCharacterSet] name:@"whitespace" min:1];
    ZKBaseParser* maybeWs = [f characters:[NSCharacterSet whitespaceAndNewlineCharacterSet] name:@"whitespace" min:0];
    ZKBaseParser* cut = [f cut];
    
    // constructs a seq parser for each whitespace separated token, e.g. given input "NULLS LAST" will generate
    // seq:"NULLS", ws, "LAST".
    ZKBaseParser*(^tokenSeqType)(NSString*,TokenType) = ^ZKBaseParser*(NSString *t, TokenType type) {
        NSArray<NSString*>* tokens = [t componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSMutableArray *seq = [NSMutableArray arrayWithCapacity:tokens.count *2];
        NSEnumerator *e = [tokens objectEnumerator];
        [seq addObject:[f eq:[e nextObject]]];
        do {
            NSString *next = [e nextObject];
            if (next == nil) break;
            [seq addObject:ws];
            [seq addObject:[f eq:next]];
        } while(true);
        return [[f seq:seq] onMatch:^ZKParserResult*(ZKArrayParserResult*r) {
            Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.loc];
            t.type = type;
            t.value = t;
            [r.userContext[KeyTokens] addToken:t];
            return r;
        }];
    };
    ZKBaseParser*(^tokenSeq)(NSString*) = ^ZKBaseParser*(NSString *t) {
        return tokenSeqType(t, TTKeyword);
    };
    // USING is not in the doc, but appears to not be allowed
    // ORDER & OFFSET are issues for our parser, but not the sfdc one.
    NSSet<NSString*>* keywords = [NSSet setWithArray:[@"ORDER OFFSET USING   AND ASC DESC EXCLUDES FIRST FROM GROUP HAVING IN INCLUDES LAST LIKE LIMIT NOT NULL NULLS OR SELECT WHERE WITH" componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    BOOL(^ignoreKeywords)(NSObject*) = ^BOOL(NSObject *v) {
        NSString *s = (NSString *)v;
        return [keywords containsObject:[s uppercaseString]];
    };
    ZKBaseParser* commaSep = [f seq:@[maybeWs, [f eq:@","], maybeWs]];
    ZKBaseParser* ident = [f characters:[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"]
                               name:@"identifier"
                                min:1];
    
    // SELECT LIST
    ZKParserRef *selectStmt = [f parserRef];
    ZKBaseParser *alias = [[f zeroOrOne:[[f seq:@[ws, ident]] onMatch:pick(1)] ignoring:ignoreKeywords] onMatch:^ZKParserResult *(ZKParserResult *r) {
        if (r.val != [NSNull null]) {
            Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.loc];
            t.type = TTAliasDecl;
            [r.userContext[KeyTokens] addToken:t];
            r.val = t;
        }
        return r;
    }];
    ZKBaseParser* fieldOnly = [[f oneOrMore:ident separator:[f eq:@"."]] onMatch:^ZKParserResult *(ZKArrayParserResult *r) {
        Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.loc];
        t.type = TTFieldPath;
        [r.userContext[KeyTokens] addToken:t];
        r.val = t;
        return r;
    }];
    fieldOnly.debugName = @"fieldOnly";
    ZKBaseParser* fieldAndAlias = [f seq:@[fieldOnly, alias]];
    fieldAndAlias.debugName = @"field";
    
    ZKParserRef *fieldOrFunc = [f parserRef];
    ZKBaseParser* func = [[f seq:@[ident,
                              maybeWs,
                              [f eq:@"("],
                              maybeWs,
                              [f oneOrMore:fieldOrFunc separator:commaSep],
                              maybeWs,
                              [f eq:@")"],
                              alias
                            ]] onMatch:^ZKParserResult*(ZKArrayParserResult*r) {
    
        Token *fn = [Token txt:r.userContext[KeySoqlText] loc:r.child[0].loc];
        fn.type = TTFunc;
        [r.userContext[KeyTokens] addToken:fn];
        // TODO, do we need a FuncEnd token and/or additional annotations for the args?
        return r;
    }];
    
    fieldOrFunc.parser = [f firstOf:@[func, fieldAndAlias]];
    ZKBaseParser *nestedSelectStmt = [[f seq:@[[f eq:@"("], selectStmt, [f eq:@")"]]] onMatch:^ZKParserResult*(ZKArrayParserResult*r) {
        // Similar to Func, I think we'd need start/stop tokens for this.
        Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.loc];
        t.type = TTNestedSelect;
        [r.userContext[KeyTokens] addToken:t];
        r.val = t;
        return r;
    }];
    ZKBaseParser *typeOfWhen = [[f seq:@[tokenSeq(@"WHEN"), cut, ws, ident, ws, tokenSeq(@"THEN"), ws,
                                         [f oneOrMore:fieldOnly separator:commaSep]]] onMatch:^ZKParserResult *(ZKArrayParserResult *r) {
        Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.child[3].loc];
        t.type = TTSObject;
        [r.userContext[KeyTokens] addToken:t];
        return r;
    }];
    ZKBaseParser *typeOfElse = [f seq:@[tokenSeq(@"ELSE"), ws, [f oneOrMore:fieldOnly separator:commaSep]]];
    ZKBaseParser *typeOf = [[f seq:@[
                                tokenSeq(@"TYPEOF"), ws,
                                ident, ws,
                                [f oneOrMore:typeOfWhen separator:ws], maybeWs,
                                [f zeroOrOne:typeOfElse], ws,
                                tokenSeq(@"END")]] onMatch:^ZKParserResult *(ZKArrayParserResult *r) {
        Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.child[2].loc];
        t.type = TTRelationship;
        [r.userContext[KeyTokens] addToken:t];
        return r;
    }];
    typeOfWhen.debugName = @"typeofWhen";
    typeOfElse.debugName = @"typeofElse";
    
    ZKBaseParser* selectExprs = [f oneOrMore:[f firstOf:@[func, typeOf, fieldAndAlias, nestedSelectStmt]] separator:commaSep];
//    ZKBaseParser *countOnly = [[f seq:@[[f eq:@"count"], maybeWs, [f eq:@"("], maybeWs, [f eq:@")"]]] onMatch:^ZKParserResult *(ZKArrayParserResult *r) {
//        // Should we just let count() be handled by the regular func matcher? and not deal with the fact it can only
//        // appear on its own.
//        r.val =@[[SelectFunc name:[r.child[0] posString] args:@[] alias:nil loc:r.loc]];
//        return r;
//    }];
//    selectExprs = [f oneOf:@[selectExprs, countOnly]];

    /// FROM
    ZKBaseParser *objectRef = [[f seq:@[ident, alias]] onMatch:^ZKParserResult *(ZKArrayParserResult *r) {
        Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.child[0].loc];
        t.type = TTSObject;
        [r.userContext[KeyTokens] addToken:t];
        if (![r childIsNull:1]) {
            t = [t tokenOf:r.child[1].loc];
            t.type = TTAliasDecl;
            [r.userContext[KeyTokens] addToken:t];
        }
        return r;
    }];
    ZKBaseParser *objectRefs = [[f seq:@[objectRef, [f zeroOrOne:
                                [[f seq:@[commaSep, [f oneOrMore:fieldAndAlias separator:commaSep]]] onMatch:pick(1)]]]]
                          onMatch:^ZKParserResult *(ZKArrayParserResult*r) {
        
        // TODO, the fieldAndAlias tokens generated have the wrong type in this case.
//        r.val = [From sobject:r.child[0].val
//                      related:[r childIsNull:1] ? @[] : [r.child[1].val valueForKey:@"val"]
//                          loc:r.loc];
        return r;
    }];
    
    /// WHERE
    ZKBaseParser *operator = [[f oneOfTokens:@"< <= > >= = != LIKE"] onMatch:^ZKParserResult *(ZKParserResult *r) {
        Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.loc];
        t.type = TTOperator;
        [r.userContext[KeyTokens] addToken:t];
        return r;
    }];
    ZKBaseParser *opIncExcl = [[f oneOfTokens:@"INCLUDES EXCLUDES"]  onMatch:^ZKParserResult *(ZKParserResult *r) {
        Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.loc];
        t.type = TTOperator;
        [r.userContext[KeyTokens] addToken:t];
        return r;
    }];
    ZKBaseParser *opInNotIn = [f oneOf:@[tokenSeqType(@"IN", TTOperator), tokenSeqType(@"NOT IN", TTOperator)]];
    ZKBaseParser *literalValue = [self literalValue:f];
    ZKBaseParser *literalStringList = [[f seq:@[    [f eq:@"("], maybeWs,
                                                [f oneOrMore:[self literalStringValue:f] separator:commaSep],
                                                maybeWs, [f eq:@")"]]]
                                   onMatch:^ZKParserResult*(ZKArrayParserResult*r) {
//        NSArray* vals = [r.child[2].val valueForKey:@"val"];
//        r.val = [LiteralValueArray withValues:vals loc:r.loc];
        // TODO
        return r;
    }];
    ZKBaseParser *operatorRHS = [f oneOf:@[
        [f seq:@[operator, cut, maybeWs, literalValue]],
        [f seq:@[opIncExcl, cut, maybeWs, literalStringList]],
        [f seq:@[opInNotIn, cut, maybeWs, [f oneOf:@[literalStringList, nestedSelectStmt]]]]]];

    ZKBaseParser *baseExpr = [f seq:@[fieldOrFunc, maybeWs, operatorRHS]];

    // use parserRef so that we can set up the recursive decent for (...)
    // be careful not to use oneOf with it as that will recurse infinitly because it checks all branches.
    ZKParserRef *exprList = [f parserRef];
    ZKBaseParser *parens = [[f seq:@[[f eq:@"("], maybeWs, exprList, maybeWs, [f eq:@")"]]] onMatch:pick(2)];
    ZKBaseParser *andOrToken = [[f oneOfTokens:@"AND OR"] onMatch:^ZKParserResult *(ZKParserResult *r) {
        Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.loc];
        t.type = TTOperator;
        [r.userContext[KeyTokens] addToken:t];
        return r;
    }];
    ZKBaseParser *andOr = [f seq:@[ws, andOrToken, ws]];
    ZKBaseParser *not = [f seq:@[tokenSeqType(@"NOT", TTOperator), maybeWs]];
    exprList.parser = [f seq:@[[f zeroOrOne:not],[f firstOf:@[parens, baseExpr]], [f zeroOrOne:[f seq:@[andOr, exprList]]]]];
    
    ZKBaseParser *where = [f zeroOrOne:[f seq:@[ws ,tokenSeq(@"WHERE"), cut, ws, exprList]]];
    
    /// FILTER SCOPE
    ZKBaseParser *filterScope = [f zeroOrOne:[[f seq:@[ws, tokenSeq(@"USING SCOPE"), ws, ident]] onMatch:^ZKParserResult*(ZKArrayParserResult*r) {
        Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.child[3].loc];
        t.type = TTUsingScope;
        [r.userContext[KeyTokens] addToken:t];
        return r;
    }]];

    /// DATA CATEGORY
    ZKBaseParser *aCategory = [[ident copy] onMatch:^ZKParserResult*(ZKParserResult*r) {
        Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.loc];
        t.type = TTDataCategoryValue;
        [r.userContext[KeyTokens] addToken:t];
        return r;
    }];
    ZKBaseParser *catList = [f seq:@[[f eq:@"("], maybeWs, [f oneOrMore:aCategory separator:commaSep], maybeWs, [f eq:@")"]]];
    ZKBaseParser *catFilterVal = [f firstOf:@[catList, aCategory]];
    
    ZKBaseParser *catFilter = [[f seq:@[ident, ws, [f oneOfTokens:@"AT ABOVE BELOW ABOVE_OR_BELOW"], cut, maybeWs, catFilterVal]] onMatch:^ZKParserResult*(ZKArrayParserResult*r) {
        Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.child[2].loc];
        t.type = TTKeyword;
        [r.userContext[KeyTokens] addToken:t];
        t = [t tokenOf:r.child[0].loc];
        t.type = TTDataCategory;
        [r.userContext[KeyTokens] addToken:t];
        return r;
    }];
    ZKBaseParser *withDataCat = [f zeroOrOne:[f seq:@[ws, tokenSeq(@"WITH DATA CATEGORY"), cut, ws,
                                                       [f oneOrMore:catFilter separator:[f seq:@[ws,tokenSeqType(@"AND",TTOperator),ws]]]]]];
    
    /// GROUP BY
    ZKBaseParser *groupBy = [f seq:@[ws, tokenSeq(@"GROUP BY"), cut, ws, [f oneOrMore:fieldOrFunc separator:commaSep]]];
    ZKBaseParser *groupByFieldList = [f seq:@[[f eq:@"("], maybeWs, [f oneOrMore:fieldOrFunc separator:commaSep], maybeWs, [f eq:@")"]]];
    ZKBaseParser *groupByRollup = [f seq:@[ws, tokenSeq(@"GROUP BY ROLLUP"), cut, maybeWs, groupByFieldList]];
    ZKBaseParser *groupByCube = [f seq:@[ws, tokenSeq(@"GROUP BY CUBE"), cut, maybeWs, groupByFieldList]];
    
    ZKBaseParser *having = [f zeroOrOne:[f seq:@[ws ,tokenSeq(@"HAVING"), cut, ws, exprList]]];
    ZKBaseParser *groupByClause = [f zeroOrOne:[f seq:@[[f firstOf:@[groupByRollup, groupByCube, groupBy]], having]]];
    
    /// ORDER BY
    ZKBaseParser *ascDesc = [f seq:@[ws, [f oneOf:@[tokenSeq(@"ASC"),tokenSeq(@"DESC")]]]];
    ZKBaseParser *nulls = [f seq:@[ws, [f oneOf:@[tokenSeq(@"NULLS FIRST"), tokenSeq(@"NULLS LAST")]]]];
                                
    ZKBaseParser *orderByField = [f seq:@[fieldOrFunc, [f zeroOrOne:ascDesc], [f zeroOrOne:nulls]]];
    ZKBaseParser *orderByFields = [f zeroOrOne:[f seq:@[maybeWs, tokenSeq(@"ORDER BY"), cut, ws, [f oneOrMore:orderByField separator:commaSep]]]];
                                   
    ZKBaseParser *limit = [f zeroOrOne:[[f seq:@[maybeWs, tokenSeq(@"LIMIT"), cut, maybeWs, [f integerNumber]]] onMatch:^ZKParserResult*(ZKArrayParserResult*r) {
        Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.child[4].loc];
        t.type = TTLiteral;
        t.value = r.val;
        [r.userContext[KeyTokens] addToken:t];
        return r;
    }]];
    ZKBaseParser *offset= [f zeroOrOne:[[f seq:@[maybeWs, tokenSeq(@"OFFSET"), cut, maybeWs, [f integerNumber]]] onMatch:^ZKParserResult*(ZKArrayParserResult*r) {
        Token *t = [Token txt:r.userContext[KeySoqlText] loc:r.child[4].loc];
        t.type = TTLiteral;
        t.value = r.val;
        [r.userContext[KeyTokens] addToken:t];
        return r;
    }]];

    ZKBaseParser *forView = [f zeroOrOne:[f seq:@[maybeWs, tokenSeq(@"FOR"), cut, ws, [f firstOf:@[tokenSeq(@"VIEW"), tokenSeq(@"REFERENCE")]]]]];
    ZKBaseParser *updateTracking = [f zeroOrOne:[f seq:@[maybeWs, tokenSeq(@"UPDATE"), cut, ws,
                                                         [f firstOf:@[tokenSeq(@"TRACKING"), tokenSeq(@"VIEWSTAT")]]]]];

    /// SELECT
    selectStmt.parser = [f seq:@[maybeWs, tokenSeq(@"SELECT"), ws, selectExprs, ws, tokenSeq(@"FROM"), ws, objectRefs,
                                  filterScope, where, withDataCat, groupByClause, orderByFields, limit, offset, forView, updateTracking, maybeWs]];
    
    return selectStmt;
}


@end



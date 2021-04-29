//
//  SoqlFunction.m
//  SoqlXplorer
//
//  Created by Simon Fell on 4/27/21.
//

#import "SoqlFunction.h"
#import "CaseInsensitiveStringKey.h"
#import "SoqlToken.h"
#import <ZKSforce/ZKSforce.h>

ExampleProvider firstFieldP(NSPredicate*p) {
    return ^NSString*(ZKDescribeSObject*o) {
        for (ZKDescribeField *f in o.fields) {
            if ([p evaluateWithObject:f]) {
                return f.name;
            }
        }
        return @"Id";
    };
}
ExampleProvider firstField(NSString*p) {
    return firstFieldP([NSPredicate predicateWithFormat:p]);
}
ExampleProvider fixed(NSString*value) {
    return ^NSString*(ZKDescribeSObject*o) {
        return value;
    };
}

@implementation SoqlFuncArg
+(instancetype)arg:(TokenType)type fldPred:(NSString*)fieldFilter fnPred:(NSPredicate *)fnFilter {
    SoqlFuncArg *a = [self new];
    a.type = type;
    a.fieldFilter = [NSPredicate predicateWithFormat:fieldFilter];
    a.example = firstFieldP(a.fieldFilter);
    a.funcFilter = fnFilter;
    return a;
}

+(instancetype)arg:(TokenType)type fldPred:(NSString*)fieldFilter {
    return [self arg:type fldPred:fieldFilter fnPred:nil];
}

+(instancetype)arg:(TokenType)type ex:(ExampleProvider)ex {
    SoqlFuncArg *a = [self new];
    a.type = type;
    a.example = ex;
    return a;
}
@end

@implementation SoqlFunction

+(NSDictionary<CaseInsensitiveStringKey*,SoqlFunction*>*)all {
    SoqlFunction *cvtTz = [self fn:@"ConvertTimezone" args:@[[SoqlFuncArg arg:TTFieldPath fldPred:@"type='datetime' OR type='date'"]]];
    NSPredicate *cvzTzOnly = [NSPredicate predicateWithFormat:@"name=%@", cvtTz.name];
    SoqlFunction *geoLoc = [self fn:@"Geolocation" args:@[[SoqlFuncArg arg:TTLiteral ex:fixed(@"1.0")], [SoqlFuncArg arg:TTLiteral ex:fixed(@"1.0")]]];
    SoqlFuncArg *distGeoArg = [SoqlFuncArg arg:TTFunc ex:fixed(@"GeoLocation(1.0,1.0)")];
    distGeoArg.funcFilter = [NSPredicate predicateWithFormat:@"name=%@", geoLoc.name];
    
    NSArray<SoqlFunction*>* fns = @[
        [self fn:@"Fields" args:@[[SoqlFuncArg arg:TTKeyword ex:fixed(@"STANDARD")]]],
        [self fn:@"ToLabel" args:@[[SoqlFuncArg arg:TTFieldPath fldPred:@"type!='id' AND type!='reference'"]]],
        [self fn:@"Count" args:@[[SoqlFuncArg arg:TTFieldPath fldPred:@"aggregatable=true"]]],
        [self fn:@"Count_Distinct" args:@[[SoqlFuncArg arg:TTFieldPath fldPred:@"aggregatable=true"]]],
        [self fn:@"Avg" args:@[[SoqlFuncArg arg:TTFieldPath fldPred:@"aggregatable=true AND (type='double' OR type='integer' OR type='currency')"]]],
        [self fn:@"Sum" args:@[[SoqlFuncArg arg:TTFieldPath fldPred:@"aggregatable=true AND (type='double' OR type='integer' OR type='currency')"]]],
        [self fn:@"Min" args:@[[SoqlFuncArg arg:TTFieldPath fldPred:@"aggregatable=true AND type!='id' AND type!='reference'"]]],
        [self fn:@"Max" args:@[[SoqlFuncArg arg:TTFieldPath fldPred:@"aggregatable=true AND type!='id' AND type!='reference'"]]],
        [self fn:@"Format" args:@[[SoqlFuncArg arg:TTFieldPath | TTFunc
                                           fldPred:@"type='datetime' OR type='date' OR type='time' or type='currency' or type='double' or type='integer'"]]],    
        [self fn:@"Distance" args:@[[SoqlFuncArg arg:TTFieldPath fldPred:@"type='location'"],
                                    distGeoArg,
                                    [SoqlFuncArg arg:TTLiteral ex:fixed(@"\'mi\'")]]],
        [self fn:@"Calendar_Month" args:@[[SoqlFuncArg arg:TTFieldPath | TTFunc fldPred:@"type='datetime' OR type='date'" fnPred:cvzTzOnly]]],
        [self fn:@"Calendar_Quarter" args:@[[SoqlFuncArg arg:TTFieldPath| TTFunc fldPred:@"type='datetime' OR type='date'" fnPred:cvzTzOnly]]],
        [self fn:@"Calendar_Year" args:@[[SoqlFuncArg arg:TTFieldPath | TTFunc fldPred:@"type='datetime' OR type='date'" fnPred:cvzTzOnly]]],
        [self fn:@"Day_In_Month" args:@[[SoqlFuncArg arg:TTFieldPath | TTFunc fldPred:@"type='datetime' OR type='date'" fnPred:cvzTzOnly]]],
        [self fn:@"Day_In_Week" args:@[[SoqlFuncArg arg:TTFieldPath | TTFunc fldPred:@"type='datetime' OR type='date'" fnPred:cvzTzOnly]]],
        [self fn:@"Day_In_Year" args:@[[SoqlFuncArg arg:TTFieldPath | TTFunc fldPred:@"type='datetime' OR type='date'" fnPred:cvzTzOnly]]],
        [self fn:@"Day_Only" args:@[[SoqlFuncArg arg:TTFieldPath | TTFunc fldPred:@"type='datetime'" fnPred:cvzTzOnly]]],
        [self fn:@"Fiscal_Month" args:@[[SoqlFuncArg arg:TTFieldPath | TTFunc fldPred:@"type='datetime' OR type='date'" fnPred:cvzTzOnly]]],
        [self fn:@"Fiscal_Quarter" args:@[[SoqlFuncArg arg:TTFieldPath | TTFunc fldPred:@"type='datetime' OR type='date'" fnPred:cvzTzOnly]]],
        [self fn:@"Fiscal_Year" args:@[[SoqlFuncArg arg:TTFieldPath | TTFunc fldPred:@"type='datetime' OR type='date'" fnPred:cvzTzOnly]]],
        [self fn:@"Hour_In_Day" args:@[[SoqlFuncArg arg:TTFieldPath | TTFunc fldPred:@"type='datetime'" fnPred:cvzTzOnly]]],
        [self fn:@"Week_In_Month" args:@[[SoqlFuncArg arg:TTFieldPath | TTFunc fldPred:@"type='datetime' OR type='date'" fnPred:cvzTzOnly]]],
        [self fn:@"Week_In_Year" args:@[[SoqlFuncArg arg:TTFieldPath | TTFunc fldPred:@"type='datetime' OR type='date'" fnPred:cvzTzOnly]]],
        
        [self fn:@"ConvertCurrency" args:@[[SoqlFuncArg arg:TTFieldPath fldPred:@"type='currency'"]]],
        cvtTz, geoLoc
    ];
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:fns.count];
    for (SoqlFunction *f in fns) {
        [d setObject:f forKey:[CaseInsensitiveStringKey of:f.name]];
    }
    return [NSDictionary dictionaryWithDictionary:d];
}

+(instancetype)fn:(NSString*)name args:(NSArray<SoqlFuncArg*>*)args {
    SoqlFunction *f = [self new];
    f.name = name;
    f.args = args;
    return f;
}

-(Completion*)completionOn:(ZKDescribeSObject*)primary {
    NSMutableString *s = [NSMutableString stringWithCapacity:32];
    NSInteger posAtEndOfFirstArg = 0;
    [s appendString:self.name];
    if (self.args.count > 0) {
        [s appendString:@"("];
        NSEnumerator<SoqlFuncArg*> *e = [self.args objectEnumerator];
        [s appendString:e.nextObject.example(primary)];
        posAtEndOfFirstArg = s.length;
        SoqlFuncArg *arg = e.nextObject;
        while (arg != nil) {
            [s appendString:@","];
            [s appendString:arg.example(primary)];
            arg = e.nextObject;
        }
        [s appendString:@")"];
    }
    Completion *fc = [Completion txt:self.name type:TTFunc];
    fc.finalInsertionText = s;
    if (posAtEndOfFirstArg > 0) {
        fc.onFinalInsert = moveSelection(-(s.length-posAtEndOfFirstArg));
    }
    return fc;
}

@end
